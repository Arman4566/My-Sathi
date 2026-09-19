# Sathi X-ray AI service
#
# A small, standalone FastAPI service that Sathi's Node backend calls
# for the "AI Diagnostic Report" chest X-ray feature. Deliberately kept
# separate from the Node backend because it needs PyTorch + a real
# pretrained model, which don't belong in a lightweight Node deployment.
#
# See xray_model.py and gradcam.py for the important disclaimers about
# what this model actually is (a research-grade, non-FDA-cleared
# classifier) and what it can't do (anything other than frontal chest
# X-rays).
from __future__ import annotations

import base64
import io
import os
import tempfile

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image

import gradcam
import image_quality
import xray_model as model_module

app = FastAPI(title="Sathi X-ray AI Service")

# Threshold labels for how strongly the model's top pathology score
# stands out. Deliberately NOT using alarming clinical words like
# "Critical"/"Severe" — this is an unvalidated research model's
# threshold crossing, not a clinician's severity assessment. See the
# long comment in backend/xray_reports.js (buildPdf) for how these get
# rendered in the PDF.
def confidence_band(prob: float) -> str:
    if prob >= 0.75:
        return "High"
    if prob >= 0.40:
        return "Moderate"
    return "Low"


def looks_like_xray(bgr: np.ndarray) -> bool:
    """Best-effort sanity check, not a guarantee: chest X-rays are
    near-grayscale. A brightly colored photo (e.g. a snapshot of a
    person, a document, a colorful ultrasound) will usually fail this
    and gets flagged as a warning rather than silently scored."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    saturation = hsv[:, :, 1].mean()
    return saturation < 25  # low saturation ~= grayscale-ish


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):
    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="empty_file")

    # Persist to a temp file — torchxrayvision's preprocessing pipeline
    # (skimage.io.imread) works off a path, and this also lets OpenCV
    # re-read it independently for the quality/Grad-CAM steps below.
    suffix = os.path.splitext(file.filename or "")[1] or ".png"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        bgr = cv2.imread(tmp_path, cv2.IMREAD_COLOR)
        if bgr is None:
            raise HTTPException(status_code=400, detail="unreadable_image")
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

        warnings = []
        if not looks_like_xray(bgr):
            warnings.append(
                "This image doesn't look like a typical grayscale chest X-ray "
                "(it appears to have color). Results below may not be meaningful "
                "— please double check the correct image was uploaded."
            )

        quality = image_quality.assess_image_quality(gray)

        try:
            probabilities = model_module.predict(tmp_path)
        except Exception as exc:  # model/preprocessing failure
            raise HTTPException(status_code=422, detail=f"model_inference_failed: {exc}")

        findings = sorted(
            (
                {"label": label, "confidence": round(prob, 4), "confidenceBand": confidence_band(prob)}
                for label, prob in probabilities.items()
            ),
            key=lambda f: f["confidence"],
            reverse=True,
        )
        primary = findings[0]

        # Grad-CAM for the primary finding only (matches the sample
        # report's single "class-specific Grad-CAM" section; running it
        # for every pathology would be slow and mostly redundant).
        #
        # IMPORTANT: cam.remove() in the finally below detaches this
        # instance's hook from the (shared, reused) model afterward.
        # Without it, the hook stays attached and the NEXT request's
        # plain no-grad predict() call above would crash trying to
        # register a gradient hook on a tensor that doesn't require
        # one — this was a real bug caught by sending two requests in a
        # row, not just one.
        cam_model = model_module.get_model()
        cam = gradcam.GradCAM(cam_model)
        try:
            input_tensor = model_module.predict_tensor_for_gradcam(tmp_path)
            pathology_names = [p for p in cam_model.pathologies if p]
            class_idx = pathology_names.index(primary["label"])
            cam_map = cam.generate(input_tensor, class_idx)
        finally:
            cam.remove()

        # Grad-CAM is computed on the 224x224 preprocessed frame; render
        # it against a same-size view of the original for an overlay
        # that lines up, then also keep a full-resolution original for
        # display.
        preview = cv2.resize(rgb, (224, 224))
        heatmap_bgr, overlay_bgr, coverage_pct = gradcam.render_heatmap_images(cam_map, preview)

        def encode_png(bgr_img) -> str:
            ok, buf = cv2.imencode(".png", bgr_img)
            if not ok:
                raise HTTPException(status_code=500, detail="image_encode_failed")
            return base64.b64encode(buf.tobytes()).decode("ascii")

        original_png = encode_png(cv2.cvtColor(preview, cv2.COLOR_RGB2BGR))
        heatmap_png = encode_png(heatmap_bgr)
        overlay_png = encode_png(overlay_bgr)

        return JSONResponse(
            {
                "modelId": "torchxrayvision/densenet121-res224-all",
                "warnings": warnings,
                "imageQuality": quality,
                "findings": findings[:8],
                "primaryFinding": primary,
                "gradCam": {
                    "featureLayer": "densenet121.features (final conv block)",
                    "coveragePercent": round(coverage_pct, 2),
                    "threshold": 0.5,
                    "originalPng": original_png,
                    "heatmapPng": heatmap_png,
                    "overlayPng": overlay_png,
                },
            }
        )
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
