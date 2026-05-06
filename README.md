# Furiosa RNGD Validator

Validation suite for Furiosa RNGD-based servers. Runs three phases -- hardware diagnostics, P2P bandwidth benchmarks, and LLM stress tests -- and produces per-phase HTML reports, a run-level `index.html`, and a machine-readable `summary.json`. Can be run directly on a configured host or via Docker.

## Prerequisites

**Common**

- Furiosa NPUs physically installed and visible to the OS. With `debugfs` mounted at `/sys/kernel/debug`, each NPU must appear as `/sys/kernel/debug/rngd/mgmt<N>`; a missing path here causes every phase to exit with "No NPUs detected".
- A [Hugging Face access token](https://huggingface.co/settings/tokens) with access to the models the stress phase loads:
  - [`meta-llama/Llama-3.1-8B-Instruct`](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct)
  - [`Qwen/Qwen2.5-0.5B-Instruct`](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)

> If you haven't accepted the terms of use for these models, visit each model page on Hugging Face and agree before proceeding.

**Docker**

- Docker installed on the host; the rest of the stack lives inside the image.

**Native (without Docker)**

- Ubuntu 24.04 (or an `apt`-compatible distribution) with `sudo`.
- System packages: `bash pciutils python3 python3-pip ca-certificates jq curl gnupg wget git`.
- `furiosa-toolkit-rngd` installed from the Furiosa apt repository. Refer to the Dockerfile for the exact `apt` source line.
- Python packages pinned to the reference Dockerfile:
  - `furiosa-llm==2026.1.0` (from the Furiosa private PyPI index `https://asia-northeast3-python.pkg.dev/furiosa-ai/pypi/simple`)
  - `pillow`, `urllib3<2`, `more-itertools<11.0`
  - `torchvision` uninstalled if a transitive install pulled it in, matching the Dockerfile.
- `FURIOSA_SKIP_PERT_DEPLOY=1` exported before invocation.
- Root privileges at runtime (hardware access via `debugfs`, `setpci`, and `dmesg`).

## Available Tests

Three validation phases are available; the `RUN_TESTS` environment variable picks a subset (comma-separated, default runs all three).

| Value | Description |
|---|---|
| `diag` | Hardware diagnostics: sensors, PCIe link, AER errors, power sense |
| `p2p` | NPU-to-NPU P2P bandwidth benchmark (latency + throughput for all pairs) |
| `stress` | LLM serving stress test: fixed-length and ShareGPT benchmarks on each NPU |

## Running Without Docker

```bash
export HF_TOKEN=your_huggingface_token

# Run all phases
sudo HF_TOKEN=$HF_TOKEN bash entrypoint.sh

# Run a subset
sudo HF_TOKEN=$HF_TOKEN RUN_TESTS=stress bash entrypoint.sh
sudo HF_TOKEN=$HF_TOKEN RUN_TESTS=diag,stress bash entrypoint.sh
```

> `sudo` is required for hardware access. `HF_TOKEN` must be forwarded explicitly because `sudo` drops the parent shell's environment.

## Running With Docker

### Build

```bash
docker build --progress=plain -t furiosa-rngd-validator:2026.1.0 .
```

Or use `make build`.

### Run

```bash
export HF_TOKEN=your_huggingface_token

docker run --rm -it --privileged \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  -v $(pwd)/outputs:/root/furiosa-server-validation-tool/outputs \
  -e HF_TOKEN=$HF_TOKEN \
  -e RUN_TESTS=diag,p2p,stress \
  furiosa-rngd-validator:2026.1.0
```

Or use `make run`.

## Results

Each run writes a single directory tree:

```
outputs/run_<TIMESTAMP>/
  ├── diag/         PF_result.{log,html}, diag.yaml, dmesg, exit_code.txt
  ├── p2p/          PF_result.{log,html}, lspci-*, dmesg, exit_code.txt
  ├── stress/       PF_result.{log,html}, sensor_log_*.csv, per-model results, exit_code.txt
  ├── logs/stress/  per-model per-NPU serve.log / fixed.log / sharegpt.log
  ├── index.html    run-level entry point (open this first)
  └── summary.json  machine-readable summary
```

`index.html` shows each phase's PASS/FAIL badge with links to its report. `summary.json` carries the same information in a machine-readable form:

```json
{
  "overall_status": "pass",
  "phases": [
    {"phase": "diag", "exit_code": 0, "status": "pass", "report": "diag/PF_result.html"},
    {"phase": "p2p",  "exit_code": 0, "status": "pass", "report": "p2p/PF_result.html"},
    {"phase": "stress", "exit_code": 0, "status": "pass", "report": "stress/PF_result.html"}
  ]
}
```

`overall_status` is `pass` when every phase that ran exited 0, `fail` when any phase exited non-zero, and `unknown` if a phase did not record an exit code.

### How PASS/FAIL is determined

**`diag`** compares the YAML produced by `rngd-diag` against these thresholds:

| Item | Threshold |
|---|---|
| Sensor `ta`, `npu_ambient`, `hbm`, `soc`, `pe` | 10.0 -- 80.0 °C |
| Sensor `p_rms_total` | 30.0 -- 60.0 W |
| `power_sense.value` | 2.0 or 3.0 |
| PCIe link speed | 32GT/s |
| PCIe link width | x16 |
| AER `total_err_fatal` | 0 |

**`p2p`** reports every NPU pair's latency and throughput. The phase itself exits 0 unless `furiosa-hal-bench` fails outright; a per-pair threshold-based verdict is not applied here and operators should compare the numbers against their platform's expected envelope.

**`stress`** passes per NPU when both the fixed-length and ShareGPT benchmark complete without error. Any non-zero benchmark exit or serve-startup timeout makes the phase exit 1.

## Troubleshooting

**"No NPUs detected"** -- `/sys/kernel/debug/rngd/mgmt<N>` is missing. Confirm the driver is loaded and that the container (if any) uses `-v /sys/kernel/debug:/sys/kernel/debug` with `--privileged`.

**"HF_TOKEN is not set"** -- The stress phase needs a Hugging Face token. Export `HF_TOKEN` and forward it: with `sudo`, use `sudo HF_TOKEN=$HF_TOKEN bash entrypoint.sh`; with Docker, add `-e HF_TOKEN=$HF_TOKEN`.

**Stress phase hangs at "Model on port X not ready"** -- `furiosa-llm serve` takes several minutes on first invocation (compilation + weight download). Default wait is `SERVE_READY_MAX_ATTEMPTS × SERVE_READY_INTERVAL = 30 × 60 s = 30 min`. Tune those environment variables for faster iteration.

**ACS appears to be left disabled after a P2P abort** -- `run_p2p.sh` installs an EXIT/INT/TERM trap that re-runs `lib/acs.sh --mode enable` on abort, so the normal path restores ACS. If you suspect ACS is still disabled, verify with `lspci -vvv -s <bdf> | grep ACSCtl:` and run `sudo bash scripts/lib/acs.sh --mode enable` manually.

**First stress run downloads `vllm` and `ShareGPT_V3_unfiltered_cleaned_split.json`** -- these are cached in `scripts/` on first run and re-used thereafter. On a host without outbound network, bake them into the image manually or run stress once on a connected host and copy the caches over.
