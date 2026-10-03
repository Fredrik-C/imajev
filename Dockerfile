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
      'transformers>=5.3,<6' 'peft>=0.15' 'safetensors>=0.5' 'accelerate>=1.0' && \
    python -m pip install --no-cache-dir 'einops' && \
    python -m pip install --no-cache-dir --no-deps 'flash-linear-attention==0.5.2' && \
    python -m pip install --no-cache-dir --no-deps \
      --index-url https://stable.repo.amd.com/rocm/whl-next/ 'rocm-sdk-devel==10.0.0' && \
    rocm-sdk init && \
    ROCM_DEVEL_ROOT="$(rocm-sdk path --root)" && \
    test -f "$ROCM_DEVEL_ROOT/include/hip/hip_runtime_api.h" && \
    CPATH="$ROCM_DEVEL_ROOT/include${CPATH:+:$CPATH}" HIP_ARCHITECTURES=gfx1103 \
      python -m pip install --no-cache-dir --no-build-isolation \
      'causal-conv1d==1.7.0' && \
    python -c "import torch, fla, causal_conv1d; assert torch.version.hip, 'Expected AMD ROCm PyTorch'; print('ROCm kernels imported with', torch.__version__, torch.version.hip)"

EXPOSE 8765
CMD ["python", "/app/docker/entrypoint.py"]
