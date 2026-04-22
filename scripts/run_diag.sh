#!/bin/bash
set -e

######################################
# Root check
######################################
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root"
  exit 1
fi

######################################
# Environment
######################################
OUTPUT_DIAG=${OUTPUT_DIAG:-$OUTPUT_DIR/diag_$TIMESTAMP}
LOG_DIAG=${LOG_DIAG:-$LOG_DIR/diag_$TIMESTAMP}
mkdir -p "$OUTPUT_DIAG" "$LOG_DIAG"

YAML_NAME="${OUTPUT_DIAG}/diag.yaml"
LOG_FILE="${OUTPUT_DIAG}/result_diag.log"

exec > >(tee -a "$LOG_FILE") 2>&1

######################################
# Locate binary & python code
######################################
DIAG_BIN="$VALIDATION_DIR/scripts/rngd-diag"
DECODER_BIN="$VALIDATION_DIR/scripts/rngd-diag_decoder.py"

[ -x "$DIAG_BIN" ] || { echo "ERROR: rngd-diag not found"; exit 1; }
[ -x "$DECODER_BIN" ] || { echo "ERROR: rngd-diag_decoder not found"; exit 1; }

######################################
# Run diag
######################################
VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")

SERVER_NAME="Hardware Vendor: $VENDOR
Hardware Model: $MODEL"

# hostinfo.yaml
echo "------------------------------------------" >> "$LOG_FILE"
echo "Running test on server info:" >> "$LOG_FILE"
echo "$SERVER_NAME" >> "$LOG_FILE"
echo "------------------------------------------" >> "$LOG_FILE"

echo "[1/2] Running rngd-diag..."
"$DIAG_BIN" -o "$YAML_NAME"

echo "[2/2] Decoding result..."
python3 "$DECODER_BIN" "$YAML_NAME" "$OUTPUT_DIAG"

# dmesg
sudo dmesg > "${OUTPUT_DIAG}/dmesg_$(date +%Y%m%d_%H%M%S).log"

echo "===================================="
echo "Diagnostic completed successfully"
echo "Result YAML : $YAML_NAME"
echo "Output dir  : $OUTPUT_DIAG"
echo "Log file    : $LOG_FILE"
echo "===================================="