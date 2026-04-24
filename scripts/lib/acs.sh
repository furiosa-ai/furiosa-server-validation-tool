#!/bin/bash
# Unified ACS (Access Control Services) walker for Broadcom PCIe switches.
# Walks from each Furiosa endpoint up through Broadcom switches and writes
# the ACSCtl register for every switch port that exposes the ACS capability.
#
# Usage: acs.sh --mode {enable|disable} [-d]
#
# The helper functions below are intentionally defined at module scope so
# the file can be `source`d by tests; the main walk only runs when this
# file is executed directly.

DEBUG=${DEBUG:-0}

has_acs_cap() {
  local bdf="$1"
  local out
  out="$(lspci -nn -vvv -s "${bdf#0000:}" 2>/dev/null || true)"
  if [[ "$DEBUG" -eq 1 ]]; then
    echo "----- [DBG] lspci -nn -vvv -s ${bdf#0000:} -----" >&2
    echo "$out" >&2
    echo "----- [DBG] ACS-related lines -----" >&2
    echo "$out" | grep -niE "Access Control Services|ACSCap:|ACSCtl:" >&2 || true
    echo "----------------------------------" >&2
  fi
  echo "$out" | grep -qiE "Access Control Services|ACSCap:|ACSCtl:"
}

is_broadcom_switch() {
  local bdf="$1"
  lspci -nn -s "${bdf#0000:}" 2>/dev/null | grep -qE "Broadcom|PEX8"
}

get_parent_bdf() {
  local bdf="$1"
  local dev="/sys/bus/pci/devices/$bdf"
  [[ -e "$dev" ]] || return 1
  basename "$(readlink -f "$dev/..")"
}

apply_acs_value() {
  local bdf="$1"
  local cur
  cur="$(setpci -s "${bdf#0000:}" ECAP_ACS+0x6.W 2>/dev/null || true)"
  [[ -n "$cur" ]] || return 0
  echo "  Apply ACSCtl: ${bdf#0000:}  (0x$cur -> 0x$ACS_VALUE)"
  setpci -s "${bdf#0000:}" ECAP_ACS+0x6.W=0x$ACS_VALUE
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  [[ "$EUID" -eq 0 ]] || {
    echo "ERROR: acs.sh must be run as root"
    exit 1
  }

  MODE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d)
        DEBUG=1
        shift
        ;;
      --mode)
        MODE="$2"
        shift 2
        ;;
      -h | --help)
        echo "Usage: $0 --mode {enable|disable} [-d]"
        exit 0
        ;;
      *)
        echo "ERROR: unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  case "$MODE" in
    # Source Validation | P2P Request/Completion Redirect | Upstream Forwarding
    enable) ACS_VALUE="001f" ;;
    disable) ACS_VALUE="0000" ;;
    *)
      echo "ERROR: --mode {enable|disable} required" >&2
      exit 1
      ;;
  esac

  mapfile -t ep_bdfs < <(lspci -D | awk '/Furi/{print $1}' | sort -u)

  [[ "${#ep_bdfs[@]}" -gt 0 ]] || {
    echo "ERROR: No Furiosa PCI devices found"
    exit 1
  }

  declare -A visited=()

  for ep in "${ep_bdfs[@]}"; do
    echo "=== Endpoint: ${ep#0000:} ==="
    cur="$ep"

    while true; do
      parent="$(get_parent_bdf "$cur" || true)"
      [[ -n "${parent:-}" ]] || break

      if [[ -n "${visited[$parent]+x}" ]]; then
        [[ "$DEBUG" -eq 1 ]] && echo "  [DBG] Already visited ${parent#0000:}, skipping"
        cur="$parent"
        continue
      fi
      visited["$parent"]=1

      if ! is_broadcom_switch "$parent"; then
        echo "Stop at non-Broadcom port: ${parent#0000:}"
        break
      fi

      if has_acs_cap "$parent"; then
        apply_acs_value "$parent"
      else
        echo "  Broadcom port without ACS capability: ${parent#0000:}"
      fi

      cur="$parent"
    done

    echo
  done

  echo "ACS $MODE sequence completed successfully"
fi
