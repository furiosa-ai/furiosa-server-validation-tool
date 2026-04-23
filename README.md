# Furiosa Appliance Server Validation Tool

Dockerized validation suite for Furiosa RNGD-based servers. Runs three test suites — hardware diagnostics, P2P bandwidth benchmarks, and LLM stress tests — and produces structured logs and HTML reports.

---

## Prerequisites

- Docker installed on the host
- Furiosa NPUs physically installed and visible to the OS
- A [Hugging Face access token](https://huggingface.co/settings/tokens) with access to the following models:
  - [`meta-llama/Llama-3.1-8B-Instruct`](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct)

> If you haven't accepted the terms of use for these models, visit each model page on Hugging Face and agree before proceeding.

---

## Quick Start

```bash
# 1. Export your Hugging Face token
export HF_TOKEN=your_huggingface_token

# 2. Build the image
docker build --progress=plain --build-arg HF_TOKEN=$HF_TOKEN -t furiosa-validation-tool-online:25.3.4 .

# 3. Run all tests
docker run --rm -it --privileged \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  -v $(pwd)/outputs:/root/outputs \
  -v $(pwd)/logs:/root/logs \
  furiosa-validation-tool-online:25.3.4
```

Results are saved under `./outputs/` and `./logs/` on the host.

---

## Available Tests

| Value | Description |
|---|---|
| `diag` | Hardware diagnostics: sensors, PCIe link, AER errors, power sense |
| `p2p` | NPU-to-NPU P2P bandwidth benchmark (latency + throughput for all pairs) |
| `stress` | LLM serving stress test: fixed-length and ShareGPT benchmarks on each NPU |

Control which tests run with the `RUN_TESTS` environment variable (comma-separated, default: `diag,p2p,stress`).

---

## Build

```bash
export HF_TOKEN=your_huggingface_token

docker build --progress=plain --build-arg HF_TOKEN=$HF_TOKEN -t furiosa-validation-tool-online:[version] .
```

---

## Run

```bash
docker run --rm -it --privileged \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  -v $(pwd)/outputs:/root/outputs \
  -v $(pwd)/logs:/root/logs \
  -e RUN_TESTS=diag,p2p,stress \
  furiosa-validation-tool-online:[version]
```

**Run a subset of tests:**

```bash
# Diagnostics only
docker run ... -e RUN_TESTS=diag furiosa-validation-tool-online:[version]

# Diagnostics + stress (skip P2P)
docker run ... -e RUN_TESTS=diag,stress furiosa-validation-tool-online:[version]
```

---

## Directory Structure

```
.
├── Dockerfile
├── entrypoint.sh
├── README.md
└── scripts/
    ├── ACS_disable.sh        # Disable ACS on Broadcom PCIe switches
    ├── ACS_enable.sh         # Re-enable ACS on Broadcom PCIe switches
    ├── rngd-diag             # Hardware diagnostic binary
    ├── rngd-diag_decoder.py  # Decodes diag YAML into a human-readable report
    ├── run_diag.sh           # Runs hardware diagnostics
    ├── run_p2p.sh            # Runs P2P bandwidth benchmarks
    └── run_stress.sh         # Runs LLM serving stress tests
```
