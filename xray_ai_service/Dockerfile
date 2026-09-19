FROM python:3.11-slim

# libgl1/libglib2.0-0 are needed by opencv-python-headless at import time
# on slim base images, even though we never open a display.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Downloads torchxrayvision's pretrained weights (~30MB) at build time
# rather than on the first request, so the first real request isn't
# slow and doesn't fail if the container has no outbound internet at
# runtime.
RUN python -c "import xray_model; xray_model.get_model()"

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
