# Furiosa Appliance Server Validation Tool

Validation suite for Furiosa RNGD-based servers. Runs three test phases — hardware diagnostics, P2P bandwidth benchmarks, and LLM stress tests — and produces structured logs and HTML reports.

---

## Prerequisites

- Furiosa NPUs physically installed and visible to the OS
- A [Hugging Face access token](https://huggingface.co/settings/tokens) with access to the required models:
  - [`meta-llama/Llama-3.1-8B-Instruct`](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct)

> If you haven't accepted the terms of use for these models, visit each model page on Hugging Face and agree before proceeding.

---

## Running with Docker

Docker is the recommended path — no manual dependency setup required.

### Build

```bash
docker build --progress=plain -t furiosa-validation-tool-online:[version] .
```

### Run

```bash
export HF_TOKEN=your_huggingface_token

docker run --rm -it --privileged \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  -v $(pwd)/outputs:/root/outputs \
  -v $(pwd)/logs:/root/logs \
  -e HF_TOKEN=$HF_TOKEN \
  -e RUN_TESTS=diag,p2p,stress \
  furiosa-validation-tool-online:[version]
```

Results are saved under `./outputs/` and `./logs/` on the host.

---

## Running without Docker

Use this path if the host is already configured with the Furiosa driver, firmware, and tools, and Python dependencies (`furiosa-llm==2026.1.0`, `pillow`, `urllib3<2`, `more-itertools<11.0`) are installed.

Verify `furiosa-llm` is on your `PATH`:

```bash
which furiosa-llm
```

Then run:

```bash
export HF_TOKEN=your_huggingface_token
export VALIDATION_DIR="$(pwd)"

# Run all tests
sudo HOME=$HOME HF_TOKEN=$HF_TOKEN VALIDATION_DIR=$VALIDATION_DIR bash entrypoint.sh

# Run a subset of tests
sudo HOME=$HOME HF_TOKEN=$HF_TOKEN VALIDATION_DIR=$VALIDATION_DIR RUN_TESTS=stress bash entrypoint.sh
```

Results are saved under `./outputs/` and `./logs/` (or the paths set by `OUTPUT_DIR` / `LOG_DIR`).

> `sudo` is required for hardware access. Environment variables must be passed explicitly because `sudo` does not inherit the parent shell's environment by default.

---

## Selecting Tests

Control which tests run with the `RUN_TESTS` variable (comma-separated, default: `diag,p2p,stress`).

| Value | Description |
|---|---|
| `diag` | Hardware diagnostics: sensors, PCIe link, AER errors, power sense |
| `p2p` | NPU-to-NPU P2P bandwidth benchmark (latency + throughput for all pairs) |
| `stress` | LLM serving stress test: fixed-length and ShareGPT benchmarks on each NPU |

Examples:

```bash
RUN_TESTS=stress                # stress only
RUN_TESTS=diag,stress           # skip P2P
RUN_TESTS=diag,p2p,stress       # all (default)
```

---

## Configuration

Tunable defaults live in [`scripts/config.env`](scripts/config.env) and can be overridden by passing environment variables at runtime.

**P2P benchmark**

| Variable | Default | Description |
|---|---|---|
| `P2P_BUFFER_SIZE` | `16MiB` | Transfer buffer size for each P2P pair |

**Stress test**

| Variable | Default | Description |
|---|---|---|
| `STRESS_BASE_PORT` | `8000` | Base port for the LLM serving processes |
| `STRESS_REVISION` | `v2026.1` | Model revision tag passed to the serving stack |
| `STRESS_MODELS` | `Llama-3.1-8B-Instruct:meta-llama,`<br>`Qwen2.5-0.5B-Instruct:Qwen` | Comma-separated list of models to benchmark, each as `name:org` |
| `STRESS_FIXED_TRIPLES` | `1024:1024:128,2048:1024:64,`<br>`4096:1024:32,6144:1024:16,`<br>`12288:1024:8,31744:1024:1` | Comma-separated benchmark triples as `in_len:out_len:concurrency` |

**Service readiness**

| Variable | Default | Description |
|---|---|---|
| `SERVE_READY_MAX_ATTEMPTS` | `30` | Number of health-check attempts before giving up |
| `SERVE_READY_INTERVAL` | `60` | Seconds between each health-check attempt |

**Sensor monitor**

| Variable | Default | Description |
|---|---|---|
| `SENSOR_POLL_INTERVAL` | `1` | Poll interval in seconds for the sensor monitor |

Pass overrides inline for a single run:

```bash
# Docker
docker run ... -e P2P_BUFFER_SIZE=32MiB -e STRESS_BASE_PORT=9000 furiosa-validation-tool-online:[version]

# Without Docker
sudo HOME=$HOME HF_TOKEN=$HF_TOKEN VALIDATION_DIR=$VALIDATION_DIR P2P_BUFFER_SIZE=32MiB bash entrypoint.sh
```

To change defaults permanently, edit [`scripts/config.env`](scripts/config.env) directly.
