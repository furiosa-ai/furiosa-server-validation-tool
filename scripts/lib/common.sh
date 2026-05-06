#!/bin/bash
# Common helpers for the phase scripts. Sourced, not executed.

RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# SC2034 (variable appears unused) -- GREEN, BLUE, and BOLD are consumed only
# by sourcing scripts; shellcheck cannot follow that direction.
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
# shellcheck disable=SC2034
BOLD='\033[1m'

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

detect_npu_count() {
  find /sys/kernel/debug/rngd/ -maxdepth 1 -name 'mgmt*' 2>/dev/null | wc -l
}

# Args: out_dir [timestamp]
capture_dmesg() {
  local out_dir="$1"
  local ts="${2:-${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}}"
  dmesg >"${out_dir}/dmesg_${ts}.log"
}
