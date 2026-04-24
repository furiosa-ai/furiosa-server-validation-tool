# Furiosa Appliance Server Validation Tool

Validation suite for Furiosa RNGD-based servers. Runs three test suites — hardware diagnostics, P2P bandwidth benchmarks, and LLM stress tests — and produces structured logs and HTML reports. Can be run directly on a configured host or via Docker.

---

## Prerequisites

**Common**

- Furiosa NPUs physically installed and visible to the OS
- A [Hugging Face access token](https://huggingface.co/settings/tokens) with access to the following models:
  - [`meta-llama/Llama-3.1-8B-Instruct`](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct)

> If you haven't accepted the terms of use for these models, visit each model page on Hugging Face and agree before proceeding.

**Docker only**

- Docker installed on the host

---

## Available Tests

| Value | Description |
|---|---|
| `diag` | Hardware diagnostics: sensors, PCIe link, AER errors, power sense |
| `p2p` | NPU-to-NPU P2P bandwidth benchmark (latency + throughput for all pairs) |
| `stress` | LLM serving stress test: fixed-length and ShareGPT benchmarks on each NPU |

Control which tests run with the `RUN_TESTS` environment variable (comma-separated, default: `diag,p2p,stress`).

---

## Running Without Docker

If the environment is already configured (Furiosa driver, firmware, and tools installed, and Python dependencies including `furiosa-llm==2026.1.0`, `pillow`, `urllib3<2`, and `more-itertools<11.0` available), run the validation tool directly using `entrypoint.sh`.

```bash
# Export your Hugging Face token
export HF_TOKEN=your_huggingface_token

# Run all tests
sudo HF_TOKEN=$HF_TOKEN bash entrypoint.sh

# Run a subset of tests
sudo HF_TOKEN=$HF_TOKEN RUN_TESTS=stress bash entrypoint.sh

# Diagnostics + stress (skip P2P)
sudo HF_TOKEN=$HF_TOKEN RUN_TESTS=diag,stress bash entrypoint.sh
```

Results are saved under `./outputs/` (or the path set by `OUTPUT_DIR`).

> `sudo` is required for hardware access. `HF_TOKEN` must be passed explicitly because `sudo` does not inherit the parent shell's environment by default.

---

## Running With Docker

### Build

```bash
docker build --progress=plain -t furiosa-validation-tool-online:[version] .
```

### Run

```bash
export HF_TOKEN=your_huggingface_token

# Run all tests
docker run --rm -it --privileged \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  -v $(pwd)/outputs:/root/outputs \
  -e HF_TOKEN=$HF_TOKEN \
  -e RUN_TESTS=diag,p2p,stress \
  furiosa-validation-tool-online:[version]

# Stress only
docker run ... -e HF_TOKEN=$HF_TOKEN -e RUN_TESTS=stress furiosa-validation-tool-online:[version]

# Diagnostics + stress (skip P2P)
docker run ... -e HF_TOKEN=$HF_TOKEN -e RUN_TESTS=diag,stress furiosa-validation-tool-online:[version]
```

Results are saved under `./outputs/` on the host.

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
