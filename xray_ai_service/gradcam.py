# A genuine Grad-CAM implementation (Selvaraju et al., 2017) run against
# the real model's real feature activations and real gradients for the
# specific pathology being explained. This is NOT a decorative image —
# every pixel's "heat" comes from how much that spatial location's
# activations actually influenced the model's output score for that
# pathology on this exact image.
#
# Method: hook the output of model.features (DenseNet's final conv
# feature map, before global pooling/classification), run a forward
# pass, backprop the target pathology's logit, and weight each feature
# channel by its mean gradient (the standard Grad-CAM recipe) to build a
# class-discriminative localization map.
from __future__ import annotations

import cv2
import numpy as np
import torch


class GradCAM:
    def __init__(self, model: torch.nn.Module):
        self.model = model
        self._activations: torch.Tensor | None = None
        self._gradients: torch.Tensor | None = None

        target_layer = model.features  # DenseNet121's final conv feature map
        # Keep the handle so remove() (below) can detach it after use —
        # without this, the hook stays attached to the shared model
        # instance forever, and the NEXT unrelated request (e.g. a plain
        # no-grad predict() call) crashes with "cannot register a hook
        # on a tensor that doesn't require gradient". Confirmed by
        # actually hitting this on a second real request.
        self._forward_handle = target_layer.register_forward_hook(self._forward_hook)

    def _forward_hook(self, module, inputs, output):
        self._activations = output
        # A tensor-level gradient hook, rather than a module-level
        # register_full_backward_hook, deliberately: torchxrayvision's
        # DenseNet applies an in-place ReLU immediately after this
        # feature map (see torchxrayvision/models.py's features2()), and
        # a module backward hook here conflicts with that in-place op —
        # PyTorch raises "Output 0 of BackwardHookFunctionBackward is a
        # view and is being modified inplace" (confirmed by actually
        # running this against the real model while building this).
        # Hooking the tensor's own gradient instead sidesteps that
        # entirely and is the standard, robust way to implement Grad-CAM.
        #
        # Only register the gradient hook when this forward pass is
        # actually part of a graph that will be backprop'd (requires_grad
        # True) — if some other code path forwards through this same
        # model without gradients (e.g. a plain inference call), output
        # won't require grad and register_hook would raise.
        if output.requires_grad:
            output.register_hook(self._save_gradient)

    def _save_gradient(self, grad):
        self._gradients = grad

    def remove(self):
        """Detaches this instance's forward hook from the model.
        MUST be called (ideally in a try/finally) once you're done with
        this GradCAM instance — the model object is shared/reused across
        requests, so a hook left attached will interfere with the next
        request. See the comment in __init__ above for what happens if
        you forget this."""
        self._forward_handle.remove()

    def generate(self, input_tensor: torch.Tensor, class_idx: int) -> np.ndarray:
        """Returns a (H, W) float32 array in [0, 1] at the feature map's
        native resolution — resize_overlay() below scales it up to match
        the original image."""
        self.model.zero_grad()
        output = self.model(input_tensor)
        score = output[0, class_idx]
        score.backward(retain_graph=True)

        activations = self._activations[0]  # (C, h, w)
        gradients = self._gradients[0]  # (C, h, w)

        # Global-average-pool the gradients per channel -> importance
        # weight for that channel, per the original Grad-CAM paper.
        weights = gradients.mean(dim=(1, 2))  # (C,)

        cam = torch.zeros(activations.shape[1:], dtype=torch.float32)
        for i, w in enumerate(weights):
            cam += w * activations[i]

        cam = torch.relu(cam)  # only positive influence, per the paper
        cam = cam.detach().numpy()

        cam_max = cam.max()
        if cam_max > 0:
            cam = cam / cam_max
        return cam


def render_heatmap_images(cam: np.ndarray, original_rgb: np.ndarray, alpha: float = 0.45):
    """Turns the raw (H, W) 0-1 CAM into the same three-panel look as the
    sample report: heatmap alone (JET colormap) and heatmap overlaid on
    the original image. Returns (heatmap_bgr, overlay_bgr, coverage_pct)
    where coverage_pct is the real, computed percentage of pixels above
    a visualization threshold — the same "attention coverage" style
    figure the sample PDF shows, but genuinely measured from this CAM
    rather than a fixed/typical-looking number."""
    h, w = original_rgb.shape[:2]
    cam_resized = cv2.resize(cam, (w, h), interpolation=cv2.INTER_CUBIC)
    cam_resized = np.clip(cam_resized, 0, 1)

    heatmap = cv2.applyColorMap((cam_resized * 255).astype(np.uint8), cv2.COLORMAP_JET)
    original_bgr = cv2.cvtColor(original_rgb, cv2.COLOR_RGB2BGR)
    overlay = cv2.addWeighted(original_bgr, 1 - alpha, heatmap, alpha, 0)

    threshold = 0.5  # matches the sample report's visualization threshold
    coverage_pct = float((cam_resized > threshold).mean() * 100)

    return heatmap, overlay, coverage_pct
