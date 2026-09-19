# Genuinely computed image-quality signals, in the same spirit as the
# sample report's "Blur Score / Brightness / Noise" table — but these
# numbers come from actual pixel statistics on the uploaded image, not a
# placeholder. They're heuristics (not a validated image-QA product),
# which is stated plainly in the PDF disclaimer.
from __future__ import annotations

import cv2
import numpy as np


def assess_image_quality(gray: np.ndarray) -> dict:
    # Blur: variance of the Laplacian. Lower = blurrier. This is a
    # standard, well-known heuristic (Pech-Pacheco et al., 2000).
    blur_score = float(cv2.Laplacian(gray, cv2.CV_64F).var())

    brightness = float(gray.mean())

    # Noise: estimate via the residual after a median-blur denoise —
    # a simple, common proxy for sensor/compression noise.
    denoised = cv2.medianBlur(gray, 3)
    noise = float(np.std(gray.astype(np.float32) - denoised.astype(np.float32)))

    if blur_score < 30:
        quality_label = "Poor"
        note = "Significant blur detected — consider re-uploading a sharper image."
    elif blur_score < 80:
        quality_label = "Fair"
        note = "Mild blur detected."
    else:
        quality_label = "Good"
        note = "No significant blur detected."

    if brightness < 40:
        note += " Image appears quite dark, which can obscure detail."
    elif brightness > 220:
        note += " Image appears very bright/overexposed, which can obscure detail."

    return {
        "quality": quality_label,
        "blurScore": round(blur_score, 2),
        "brightness": round(brightness, 2),
        "noise": round(noise, 2),
        "note": note,
    }
