#!/usr/bin/env bats

setup() {
  # shellcheck source=../scripts/lib/acs.sh
  . "${BATS_TEST_DIRNAME}/../scripts/lib/acs.sh"

  FAKE_BIN="$(mktemp -d)"
  PATH="$FAKE_BIN:$PATH"
}

teardown() {
  rm -rf "$FAKE_BIN"
}

fake_lspci() {
  cat >"$FAKE_BIN/lspci" <<EOF
#!/bin/bash
cat <<'FAKE_OUT'
$1
FAKE_OUT
EOF
  chmod +x "$FAKE_BIN/lspci"
}

# is_broadcom_switch should succeed when lspci output names Broadcom as the
# upstream port vendor.
@test "is_broadcom_switch matches Broadcom vendor string" {
  fake_lspci "00:00.0 PCI bridge: Broadcom Inc. upstream port"
  run is_broadcom_switch "00:00.0"
  [[ "$status" -eq 0 ]]
}

# is_broadcom_switch should reject devices whose lspci output has neither
# "Broadcom" nor "PEX8".
@test "is_broadcom_switch rejects non-matching vendor" {
  fake_lspci "00:00.0 Intel Corporation PCI Express Root Port"
  run is_broadcom_switch "00:00.0"
  [[ "$status" -ne 0 ]]
}

# has_acs_cap should succeed when lspci -vvv output contains the standard
# "Access Control Services" capability line (one of the three accepted
# patterns in the regex).
@test "has_acs_cap matches Access Control Services capability" {
  fake_lspci "Capabilities: [200 v1] Access Control Services"
  run has_acs_cap "00:00.0"
  [[ "$status" -eq 0 ]]
}

# has_acs_cap should reject output that has no ACS-related lines at all.
@test "has_acs_cap rejects output without ACS capability" {
  fake_lspci "00:00.0 Device without the ACS capability block"
  run has_acs_cap "00:00.0"
  [[ "$status" -ne 0 ]]
}
