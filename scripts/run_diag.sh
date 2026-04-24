#!/bin/bash
set -euo pipefail

[ "$EUID" -eq 0 ] || { echo "ERROR: This script must be run as root"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

OUTPUT_DIAG=${OUTPUT_DIAG:-$RUN_DIR/diag}
mkdir -p "$OUTPUT_DIAG"

YAML_NAME="${OUTPUT_DIAG}/diag.yaml"
LOG_FILE="${OUTPUT_DIAG}/result_diag.log"

exec > >(tee -a "$LOG_FILE") 2>&1

DIAG_BIN="$VALIDATOR_DIR/scripts/rngd-diag"
TOOLS_DIR="$VALIDATOR_DIR/scripts/tools"

[ -x "$DIAG_BIN" ] || { echo "ERROR: rngd-diag not found"; exit 1; }
[ -d "$TOOLS_DIR/rngd_diag_decoder" ] || { echo "ERROR: rngd_diag_decoder package not found"; exit 1; }

VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")

echo "------------------------------------------"
echo "Hardware Vendor: $VENDOR"
echo "Hardware Model:  $MODEL"
echo "------------------------------------------"

echo "[1/2] Running rngd-diag..."
"$DIAG_BIN" -o "$YAML_NAME"

echo "[2/2] Decoding result..."
PYTHONPATH="$TOOLS_DIR" python3 -m rngd_diag_decoder "$YAML_NAME" "$OUTPUT_DIAG"

capture_dmesg "$OUTPUT_DIAG" "$(date +%Y%m%d_%H%M%S)"

echo "===================================="
echo "Diagnostic completed successfully"
echo "Result YAML : $YAML_NAME"
echo "Output dir  : $OUTPUT_DIAG"
echo "Log file    : $LOG_FILE"
echo "===================================="
