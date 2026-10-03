# Docker API server (AMD ROCm)

This runs the pinned `imajev-4b` adapter and its Qwen3.5-4B base model in a ROCm PyTorch container. It exposes the typed-decision route used by the OpenRouter Jev tutorial at `POST /api/alpha/decisions`, as well as the repository's `POST /v1/systemone` route.

The OpenRouter tutorial calls a Jev-specific API, not `/v1/chat/completions`. This server implements that same request format: `model`, `state`, and `questions`, with `noul`, `choice`, and `score` types. It returns `id`, `provider`, `model`, `answers`, and `usage`; answers also include Imajev's `unknown_probability` and `abstained` fields. Image data URLs in the state are accepted as an Imajev extension.

## Host requirements

For the Radeon 780M, use **Ubuntu 24.04.4 with the OEM 6.17 kernel** and the ROCm 10.0 generation runtime image selected below. AMD's current compatibility matrix lists Radeon 780M (`gfx1103`) and Ubuntu 24.04.4 / OEM 6.17 for Ryzen APUs. The `rocm/pytorch` container supplies ROCm user-space libraries and PyTorch. The host only needs the Linux `amdgpu` kernel driver and device nodes; do not install a second ROCm/PyTorch stack on the host.

Install the supported kernel, reboot, and confirm the running kernel:

```sh
sudo apt update
sudo apt install -y linux-oem-24.04 linux-firmware
sudo reboot
uname -r
```

The result should include `6.17`. Check that the kernel exposed the GPU compute devices:

```sh
ls -l /dev/kfd /dev/dri/renderD*
```

Install Docker Engine and the Docker Compose plugin using Docker's Ubuntu instructions. Confirm `docker --version` and `docker compose version` work. No NVIDIA Container Toolkit or host ROCm libraries are needed.

If you are running a different Ubuntu/kernel combination, check AMD's [ROCm 10.0 compatibility matrix](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html) before installing; the kernel driver and ROCm user-space versions must be compatible. ROCm support for integrated graphics has changed between ROCm releases.

## Start

From the repository root, create `.env` with a private bearer key. `openssl` can generate one:

```sh
printf 'IMAJEV_API_KEY=%s\n' "$(openssl rand -hex 32)" > .env
chmod 600 .env
```

If your host's `video` or `render` group IDs are not 44 and 109, put the actual numeric IDs in `.env` too:

```sh
getent group video render
# Add lines such as VIDEO_GID=44 and RENDER_GID=109 to .env if needed.
```

Build and start the service:

```sh
docker compose up -d --build
docker compose logs -f imajev-api
```

The first start downloads the pinned base model and adapter into the persistent `imajev-models` Docker volume (several GB). Later starts reuse those files. The API listens on port `8765`; change the host port with `IMAJEV_PORT` in `.env`. The Compose file passes `/dev/kfd` and `/dev/dri` to the container.

Verify the loaded backend and model:

```sh
curl http://127.0.0.1:8765/v1/models
```

For a headless host on a LAN, the service port is published on the host interfaces. Keep the bearer key private and put a TLS reverse proxy in front of it if clients connect over an untrusted network. The OpenRouter-compatible route requires `Authorization: Bearer <IMAJEV_API_KEY>`; `/v1/models` is a basic unauthenticated status endpoint.

## Make a decision call

This is the OpenRouter tutorial's JSON body and endpoint path, with your local base URL and key:

```sh
set -a
. ./.env
set +a

curl http://127.0.0.1:8765/api/alpha/decisions \
  -H "Authorization: Bearer $IMAJEV_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "imajev-4b",
    "state": {
      "customer_tier": "enterprise",
      "ticket": "Checkout shows a blank screen after I click Pay."
    },
    "questions": {
      "is_bug": {
        "type": "noul",
        "instructions": "Is the customer reporting a software defect?",
        "criteria": {
          "true": "The customer describes broken or unexpected product behavior.",
          "false": "The customer is asking a question or requesting a feature."
        }
      },
      "team": {
        "type": "choice",
        "instructions": "Which team should own this ticket?",
        "criteria": {
          "payments": "Checkout, billing, or payment processing issues.",
          "frontend": "Rendering, layout, or browser compatibility issues.",
          "account": "Login, permissions, or profile issues."
        }
      },
      "urgency": {
        "type": "score",
        "instructions": "How urgent is this ticket?",
        "criteria": [
          "Can wait for the next release",
          "Should be fixed this week",
          "Blocking revenue right now"
        ]
      }
    }
  }'
```

You can point a client that supports a configurable Jev decisions URL at `http://<server>:8765/api/alpha/decisions`. It is not a Chat Completions endpoint. If using an SDK, its decision endpoint/base URL must support the `/api/alpha/decisions` path and an ordinary bearer token; OpenRouter's own account key is not used.

## GPU memory and speed

The Radeon 780M is an integrated GPU and uses system memory. On ROCm the server selects FP16 (AMD's documented validated type for Ryzen APUs); CUDA servers retain their bf16 path. 96 GB system RAM is ample for the model, but actual throughput depends on the iGPU memory bandwidth and the UMA allocation set by firmware. If GPU memory allocation fails or is unusually constrained, check BIOS/UEFI UMA frame-buffer settings and leave enough memory for Ubuntu and Docker.

The service defaults to one option-order pass (`IMAJEV_ROTATIONS=1`) to keep latency and memory use down. The public 4-rotation configuration uses `calibration-rot4.json`; to enable it, set both `IMAJEV_ROTATIONS=4` and `IMAJEV_CALIBRATION=calibration-rot4.json` in `.env`, then recreate the service with `docker compose up -d`. Calibration changes probabilities, not the selected answer. These H100 benchmark timings do not predict 780M performance.

## Useful commands

```sh
docker compose logs -f imajev-api
docker compose restart imajev-api
docker compose down
```

`docker compose down -v` also deletes the downloaded model volume. The model files will be downloaded again on the next start.

## References

- [OpenRouter Jev tutorial](https://openrouter.ai/docs/guides/community/jev-tutorial)
- [AMD ROCm compatibility matrix](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html)
- [Run ROCm Docker containers](https://rocm.docs.amd.com/en/develop/install/docker-containers.html)
- [AMD PyTorch container instructions](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/native_linux/install-pytorch.html)
