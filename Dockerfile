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
    ROCM_SITE_PACKAGES="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" && \
    ROCM_CORE_LIB="$ROCM_SITE_PACKAGES/_rocm_sdk_core/lib" && \
    ROCM_HIP_RUNTIME="$(find "$ROCM_CORE_LIB" -maxdepth 1 -name 'libamdhip64.so.*' -print -quit)" && \
    test -n "$ROCM_HIP_RUNTIME" && \
    ln -sfn "$(basename "$ROCM_HIP_RUNTIME")" "$ROCM_CORE_LIB/libamdhip64.so" && \
    CPATH="$ROCM_DEVEL_ROOT/include${CPATH:+:$CPATH}" \
    LIBRARY_PATH="$ROCM_CORE_LIB${LIBRARY_PATH:+:$LIBRARY_PATH}" HIP_ARCHITECTURES=gfx1103 \
      python -m pip install --no-cache-dir --no-build-isolation \
      'causal-conv1d==1.7.0' && \
    python -c "import torch, fla, causal_conv1d; assert torch.version.hip, 'Expected AMD ROCm PyTorch'; print('ROCm kernels imported with', torch.__version__, torch.version.hip)"

EXPOSE 8765
CMD ["python", "/app/docker/entrypoint.py"]
