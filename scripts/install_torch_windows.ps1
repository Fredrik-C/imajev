[CmdletBinding()]
param(
    # Optional CUDA version reported by nvidia-smi, for example: -CudaVersion 12.8.
    # If omitted, the script reads the maximum CUDA version supported by the installed driver.
    [string]$CudaVersion
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not $CudaVersion) {
    $nvidiaSmi = Get-Command 'nvidia-smi' -ErrorAction SilentlyContinue
    if (-not $nvidiaSmi) {
        throw "Could not find nvidia-smi. Install the NVIDIA driver, or pass -CudaVersion (for example, -CudaVersion 12.8)."
    }

    $smiOutput = (& $nvidiaSmi.Source 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "nvidia-smi failed. Install or repair the NVIDIA driver, or pass -CudaVersion explicitly."
    }
    if ($smiOutput -notmatch 'CUDA Version:\s*(\d+\.\d+)') {
        throw "Could not read the driver's CUDA compatibility version from nvidia-smi. Pass -CudaVersion explicitly."
    }
    $CudaVersion = $Matches[1]
}

try {
    $cuda = [version]$CudaVersion
} catch {
    throw "Invalid CUDA version '$CudaVersion'. Use a value such as 12.8."
}

# These are the CUDA wheel indexes offered by the current PyTorch install selector.
# PyTorch wheels include their CUDA runtime; nvidia-smi reports the driver's supported
# CUDA level, which is what determines whether that runtime can run.
if ($cuda -ge [version]'12.8') {
    $wheelIndex = 'https://download.pytorch.org/whl/cu128'
    $wheelLabel = 'CUDA 12.8'
} elseif ($cuda -ge [version]'12.6') {
    $wheelIndex = 'https://download.pytorch.org/whl/cu126'
    $wheelLabel = 'CUDA 12.6'
} else {
    throw "The detected CUDA level is $CudaVersion. This installer supports CUDA 12.6+ wheel indexes; update the NVIDIA driver or use the matching command from https://pytorch.org/get-started/locally/."
}

$pythonLauncher = Get-Command 'py' -ErrorAction SilentlyContinue
if (-not $pythonLauncher) {
    throw 'Python Launcher (py.exe) was not found. Install Python 3.12, then rerun this script.'
}

$venvPath = Join-Path $repoRoot '.venv'
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    & $pythonLauncher.Source -3.12 -m venv $venvPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create .venv with Python 3.12. Install Python 3.12 and rerun this script.'
    }
}

Write-Host "Installing PyTorch and torchvision from the $wheelLabel wheel index ($wheelIndex) into $venvPath ..."
& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'pip upgrade failed.' }

& $venvPython -m pip install torch torchvision --index-url $wheelIndex
if ($LASTEXITCODE -ne 0) { throw 'PyTorch/torchvision installation failed.' }

& $venvPython -c "import torch, torchvision; print('PyTorch:', torch.__version__); print('PyTorch CUDA runtime:', torch.version.cuda); print('torchvision:', torchvision.__version__); print('CUDA available:', torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'not detected')"
if ($LASTEXITCODE -ne 0) { throw 'PyTorch verification failed.' }

Write-Host "`nNext, activate the environment and install Imajev's serving dependencies:"
Write-Host '  .\.venv\Scripts\Activate.ps1'
Write-Host '  python -m pip install -e ".[serve]" "transformers>=5.3,<6" "peft>=0.15" "safetensors>=0.5" "accelerate>=1.0"'
