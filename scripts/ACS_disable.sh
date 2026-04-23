#!/bin/bash
set -euo pipefail

######################################
# Root check
######################################

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: ACS_disable.sh must be run as root"
  exit 1
fi

######################################
# Options
######################################

DEBUG=0
while getopts ":d" opt; do
  case "$opt" in
    d) DEBUG=1 ;;
  esac
done
shift $((OPTIND-1))

######################################
# Functions
######################################

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

clear_acs_ctl() {
  local bdf="$1"
  local cur

  cur="$(setpci -s "${bdf#0000:}" ECAP_ACS+0x6.W 2>/dev/null || true)"
  [[ -n "$cur" ]] || return 0

  echo "  Clear ACSCtl: ${bdf#0000:}  (0x$cur -> 0x0000)"
  setpci -s "${bdf#0000:}" ECAP_ACS+0x6.W=0x0000
}

######################################
# Main
######################################

mapfile -t ep_bdfs < <(lspci -D | awk '/Furi/{print $1}' | sort -u)

if [ "${#ep_bdfs[@]}" -eq 0 ]; then
  echo "ERROR: No Furiosa PCI devices found"
  exit 1
fi

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
      clear_acs_ctl "$parent"
    else
      echo "  Broadcom port without ACS capability: ${parent#0000:}"
    fi

    cur="$parent"
  done

  echo
done

echo "ACS disable sequence completed successfully"
