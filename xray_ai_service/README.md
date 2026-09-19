# Sathi X-ray AI Service

A standalone Python service that runs a **real, pretrained chest X-ray
classification model** and computes a **real Grad-CAM heatmap** — this is
what backs Sathi's "AI Diagnostic Report" feature for chest X-rays. It's
kept separate from the main Node backend because it needs PyTorch, which
doesn't belong in a lightweight Node deployment.

## What this actually is (please read)

- **Model**: [torchxrayvision](https://github.com/mlmed/torchxrayvision)'s
  `densenet121-res224-all` — a DenseNet121 trained across several public
  chest X-ray datasets (NIH ChestX-ray14, CheXpert, PadChest, MIMIC-CXR,
  and others). It's a real, published research model with real learned
  weights — not a language model guessing.
- **Confidence scores** are the model's genuine sigmoid output per
  pathology (0–100%), not invented numbers.
- **Grad-CAM heatmap** is computed from the model's actual gradients and
  activations for the top-scoring pathology on this specific image — the
  colored region really does show where the model's attention was
  concentrated.

## What this is NOT

- **Not FDA/CE cleared, not clinically validated.** It's a research
  artifact. Public chest X-ray datasets are known to have labeling noise
  and demographic/equipment biases; the model can be confidently wrong.
- **Only works on frontal chest X-rays.** It has no concept of
  ultrasound, bone X-rays of limbs, CT, MRI, etc. Feeding it anything
  else will still return numbers — they'll just be meaningless.
- **Not a replacement for a radiologist.** The generated PDF carries the
  same disclaimer language throughout for this reason.

## Running locally

```bash
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

First request (or `docker build`, see below) downloads the pretrained
weights (~30MB) automatically via torchxrayvision.

## API

`POST /analyze` — multipart form upload, field name `file`, containing
the X-ray image (JPEG/PNG).

Returns JSON: `imageQuality` (real, computed blur/brightness/noise),
`findings` (all pathologies the model predicts, sorted by confidence),
`primaryFinding`, and `gradCam` (base64 PNGs: original/heatmap/overlay,
plus the real computed attention-coverage percentage).

## Deploying

```bash
docker build -t sathi-xray-service .
docker run -p 8000:8000 sathi-xray-service
```

Works on any host that runs Docker. Minimum recommended: 1 vCPU, 1–2GB
RAM. See the main project README for hosting suggestions (Hugging Face
Spaces' free CPU tier is the easiest zero-cost option; Fly.io/Render/
Railway work too on a small paid tier).

Point Sathi's Node backend at wherever you deploy this via the
`XRAY_MODEL_SERVICE_URL` environment variable (see `backend/.env.example`).

## A note on the confidence "band" (High/Moderate/Low) and why there's
## no "Critical/Severe" risk badge like some AI radiology products show

This deliberately avoids clinical-sounding severity language. A
"Critical" or "Severe" badge implies a clinical judgment — this is just
an unvalidated model's probability crossing a threshold. Overstating
that distinction is how AI tools cause real harm (false reassurance from
a low score, needless panic from a high one). The PDF instead shows the
literal number and a plain confidence band, with the same "this is not a
diagnosis" framing throughout that the original reference report used.
