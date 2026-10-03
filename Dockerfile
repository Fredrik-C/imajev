FROM rocm/pytorch:rocm10.0_ubuntu24.04_py3.12_pytorch_release_2.12.0

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HF_HOME=/models/huggingface \
    HF_HUB_DISABLE_TELEMETRY=1 \
    PYTHONPATH=/app/src:/app/scripts

WORKDIR /app
COPY . /app

# Keep the ROCm PyTorch supplied by AMD. Installing the "torch" optional extra here
# would replace it with the default CPU PyTorch wheel.
RUN python -m pip install --no-cache-dir --upgrade pip && \
    python -m pip install --no-cache-dir -e '.[serve]' \
      'transformers>=5.3,<6' 'peft>=0.15' 'safetensors>=0.5' 'accelerate>=1.0'

EXPOSE 8765
CMD ["python", "/app/docker/entrypoint.py"]
