#!/bin/bash
set -e

echo "=============================================="
echo " Furiosa Validation Tool Started (Online Mode)"
echo "=============================================="

export HOME=${HOME:-/root}
if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN is not set. Please set HF_TOKEN before running this script."
    exit 1
fi
export HF_TOKEN=$HF_TOKEN
export VALIDATION_DIR=${VALIDATION_DIR:-$HOME/furiosa-rngd-validator}
export OUTPUT_DIR=${OUTPUT_DIR:-$VALIDATION_DIR/outputs}
export LOG_DIR=${LOG_DIR:-$VALIDATION_DIR/logs}
export TIMESTAMP=$(date +%Y%m%d_%H%M%S)

cd "$VALIDATION_DIR/scripts"

RUN_TESTS=${RUN_TESTS:-"diag,p2p,stress"}

should_run_test() {
    for test in $(echo "$RUN_TESTS" | tr ',' ' '); do
        [ "$test" = "$1" ] && return 0
    done
    return 1
}

if should_run_test "diag"; then
    ./run_diag.sh
fi

if should_run_test "p2p"; then
    ./run_p2p.sh
fi

if should_run_test "stress"; then
    ./run_stress.sh
fi

echo "=============================================="
echo " All selected tests completed"
echo "=============================================="
