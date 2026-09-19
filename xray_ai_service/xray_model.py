# Loads a REAL pretrained chest X-ray classification model (not an LLM
# guessing) and exposes a single predict() function. This is the whole
# point of this separate Python service: the Node/Flutter side of Sathi
# has no way to produce a genuine, trained-model confidence score or a
# real Grad-CAM heatmap — those only exist here, where an actual CNN
# with actual learned weights is running.
#
# Model: torchxrayvision's "densenet121-res224-all" — a DenseNet121
# trained across several public chest X-ray datasets (NIH ChestX-ray14,
# CheXpert, PadChest, MIMIC-CXR, and others), released for research use
# by the torchxrayvision project (https://github.com/mlmed/torchxrayvision).
#
# IMPORTANT LIMITATIONS (please read before treating this as a medical
# device — it is not one):
# - This model is NOT FDA/CE cleared and is NOT clinically validated. It
#   is a research artifact trained on public datasets that are known to
#   have labeling noise and demographic/equipment biases.
# - It only supports FRONTAL CHEST X-RAYS. Feeding it any other body
#   part, an ultrasound, or a non-medical photo will still produce
#   numbers — they will just be meaningless. main.py does a basic sanity
#   check but cannot fully guarantee the input is actually a chest X-ray.
# - "Confidence" here is the model's raw sigmoid output per pathology
#   (0-1), i.e. how strongly ITS training data pattern-matches this
#   image to that label — not a calibrated real-world probability that
#   the patient has the condition.
from __future__ import annotations

import threading
from typing import Dict

import numpy as np
import skimage.io
import torch
import torchvision
import torchxrayvision as xrv

_MODEL_WEIGHTS = "densenet121-res224-all"

_model_lock = threading.Lock()
_model: xrv.models.DenseNet | None = None


def get_model() -> xrv.models.DenseNet:
    """Lazily loads the model once per process (first request pays the
    load cost; every request after that reuses it from memory)."""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:  # re-check inside the lock
                m = xrv.models.DenseNet(weights=_MODEL_WEIGHTS)
                m.eval()
                _model = m
    return _model


def load_and_preprocess(image_path: str) -> torch.Tensor:
    """Reproduces torchxrayvision's documented preprocessing exactly —
    getting this wrong (wrong normalization range, wrong crop/resize
    order) silently produces garbage predictions with no error, so it's
    kept in one place and not duplicated."""
    img = skimage.io.imread(image_path)

    # torchxrayvision expects a single-channel image normalized so pixel
    # values represent roughly [-1024, 1024] the way this project's
    # training data does, achieved via their normalize() helper on a
    # 0-255 input.
    img = xrv.datasets.normalize(img, 255)

    # Collapse to single channel (grayscale) if a color image was
    # uploaded (e.g. a phone photo of a printed/lightboxed X-ray).
    if img.ndim == 3:
        img = img.mean(axis=2)
    img = img[None, ...]  # add channel dim -> (1, H, W)

    transform = torchvision.transforms.Compose(
        [xrv.datasets.XRayCenterCrop(), xrv.datasets.XRayResizer(224)]
    )
    img = transform(img)

    tensor = torch.from_numpy(img).float().unsqueeze(0)  # (1, 1, 224, 224)
    return tensor


def predict(image_path: str) -> Dict[str, float]:
    """Returns {pathology_name: probability} for every pathology this
    model weight set actually predicts (torchxrayvision fills in an
    empty string for pathologies a given weight set doesn't cover —
    those are filtered out here rather than shown as a fake 0%)."""
    model = get_model()
    tensor = load_and_preprocess(image_path)
    with torch.no_grad():
        output = model(tensor)[0]
    probs = output.numpy().astype(float)
    result = {}
    for name, prob in zip(model.pathologies, probs):
        if not name:  # torchxrayvision pads unsupported labels with ''
            continue
        result[name] = float(prob)
    return result


def predict_tensor_for_gradcam(image_path: str) -> torch.Tensor:
    """Same preprocessing as predict(), but returns the tensor itself
    (with grad tracking) for gradcam.py to run a forward+backward pass
    through — kept separate so predict() can stay simple/no-grad."""
    tensor = load_and_preprocess(image_path)
    tensor.requires_grad_(True)
    return tensor
