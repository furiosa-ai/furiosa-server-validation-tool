#!/bin/bash
set -euo pipefail

######################################
# Environment & Paths
######################################
OUTPUT_STRESS=${OUTPUT_STRESS:-$OUTPUT_DIR/stress_$TIMESTAMP}
LOG_STRESS=${LOG_STRESS:-$LOG_DIR/stress_$TIMESTAMP}
mkdir -p "$OUTPUT_STRESS" "$LOG_STRESS"

export PATH="$HOME/.local/bin:$PATH"
export HF_TOKEN=$HF_TOKEN

if [ ! -d "vllm" ]; then
  git clone https://github.com/furiosa-ai/vllm.git -b add_power_monitor
fi
if [ ! -f "ShareGPT_V3_unfiltered_cleaned_split.json" ]; then
  wget https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json
fi

######################################
# Colors
######################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

######################################
# Summary Data
######################################
declare -a SUMMARY_DATA=()

######################################
# Detect NPUs
######################################
NPU_COUNT=$(ls -d /sys/kernel/debug/rngd/mgmt* 2>/dev/null | wc -l)
if [ "$NPU_COUNT" -eq 0 ]; then
  echo "Error: No NPUs detected"
  exit 1
fi
echo "Detected $NPU_COUNT NPU(s)"

BASE_PORT=8000

######################################
# Models
######################################
MODELS=(
  "EXAONE-3.5-7.8B-Instruct"
  "Llama-3.1-8B-Instruct"
  # "Qwen2.5-14B-Instruct"
  # "Llama-3.1-8B-Instruct-FP8"
)

######################################
# Helpers
######################################
get_model_id() {
  local port=$1
  curl -sf "http://localhost:$port/v1/models" \
    | jq -r '.data[0].id // empty'
}

check_models_up() {
  local ports=("$@")
  local max_attempts=30
  local attempt=1

  echo "Checking if all models are up on ports: ${ports[*]}"
  while [ $attempt -le $max_attempts ]; do
    local all_up=true
    for port in "${ports[@]}"; do
      model_id=$(get_model_id "$port" || true)
      if [ -n "$model_id" ]; then
        echo -e "${GREEN}Model on port $port is up (id: $model_id)${NC}"
      else
        echo -e "${YELLOW}Model on port $port not ready yet...${NC}"
        all_up=false
        break
      fi
    done

    if [ "$all_up" = true ]; then
      echo "All models are up!"
      return 0
    fi

    if [ $attempt -lt $max_attempts ]; then
      echo -e "${YELLOW}Attempt $attempt/$max_attempts: Not all models are up, waiting 60 seconds...${NC}"
      sleep 60
    fi
    attempt=$((attempt + 1))
  done

  echo -e "${RED}Failed to start all models after $max_attempts attempts${NC}"
  return 1
}

stop_serving() {
  local pids=("$@")

  for pid in "${pids[@]}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping serving process $pid"
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  pkill -f "furiosa-llm serve" 2>/dev/null || true
  sleep 2
}

######################################
# Benchmarks
######################################
run_fixed_benchmark() {
  local port=$1
  local model_results_dir=$2
  echo "port: $port, model_results_dir: $model_results_dir"

  local PRETRAINED_ID
  PRETRAINED_ID=$(get_model_id "$port") || return 1
  echo "PRETRAINED_ID: $PRETRAINED_ID"

  if [ -z "$PRETRAINED_ID" ]; then
    echo "Error: could not fetch model id (port=$port)"
    return 1
  fi

  local triples=(
    "1024 1024 128"
    "2048 1024 64"
    "4096 1024 32"
    "6144 1024 16"
    "12288 1024 8"
    "31744 1024 1"
  )

  for triple in "${triples[@]}"; do
    echo "triple: $triple"
    set -- $triple
    local in_len=$1 out_len=$2 conc=$3

    echo "Fixed benchmark: in=$in_len out=$out_len conc=$conc"

    python3 vllm/benchmarks/benchmark_serving.py \
      --backend vllm \
      --model "$PRETRAINED_ID" \
      --port "$port" \
      --dataset-name fixed \
      --random-input-len "$in_len" \
      --random-output-len "$out_len" \
      --max-concurrency "$conc" \
      --num-prompts "$conc" \
      --result-dir "$model_results_dir" \
      --percentile-metrics "ttft,tpot,itl,e2el" \
      --metric-percentiles "25,50,75,90,95,99" \
      --enable-device-monitor npu \
      --save-result
  done
}

run_sharegpt_benchmark() {
  local port=$1
  local model_results_dir=$2

  local PRETRAINED_ID
  PRETRAINED_ID=$(get_model_id "$port") || return 1

  if [ -z "$PRETRAINED_ID" ]; then
    echo "Error: could not fetch model id (port=$port)"
    return 1
  fi

  echo "ShareGPT benchmark"

  python3 vllm/benchmarks/benchmark_serving.py \
    --backend vllm \
    --model "$PRETRAINED_ID" \
    --port "$port" \
    --dataset-name sharegpt \
    --dataset-path "ShareGPT_V3_unfiltered_cleaned_split.json" \
    --num-prompts 1000 \
    --request-rate 32 \
    --seed 0 \
    --result-dir "$model_results_dir" \
    --percentile-metrics "ttft,tpot,itl,e2el" \
    --metric-percentiles "25,50,75,90,95,99" \
    --save-result
}

######################################
# Main
######################################
for model in "${MODELS[@]}"; do
  echo "=========================================="
  echo "Processing model: $model"
  echo "=========================================="

  declare -a serve_pids=()
  declare -a serve_ports=()

  for ((npu=0; npu<NPU_COUNT; npu++)); do
    port=$((BASE_PORT + npu))
    mkdir -p "$LOG_STRESS/${model}/npu${npu}"

    echo "Starting $model on NPU $npu (port $port)"

    model_name="furiosa-ai/$model"
    PYTHONUNBUFFERED=1 furiosa-llm serve $model_name \
      --devices "npu:$npu" \
      --port "$port" \
      --revision v2025.3.0 \
      >"$LOG_STRESS/${model}/npu${npu}/serve.log" 2>&1 &

    serve_pids+=($!)
    serve_ports+=($port)
  done

  sleep 5

  if ! check_models_up "${serve_ports[@]}"; then
    echo "Model startup failed"
    stop_serving "${serve_pids[@]}"
    for ((npu=0; npu<NPU_COUNT; npu++)); do
      SUMMARY_DATA+=("$model|NPU $npu|Fixed+ShareGPT|FAIL")
    done
    continue
  fi

  declare -a bench_pids=()
  declare -a bench_npus=()

  declare -a fixed_pids=()
  for ((i=0; i<NPU_COUNT; i++)); do
    port=${serve_ports[$i]}
    npu=$i
    result_dir="$OUTPUT_STRESS/${model}/npu${npu}"
    mkdir -p "$result_dir"

    run_fixed_benchmark "$port" "$result_dir" >"$LOG_STRESS/${model}/npu${npu}/fixed.log" 2>&1 &
    fixed_pids+=($!)
  done

  declare -a fixed_results=()
  for idx in "${!fixed_pids[@]}"; do
    if wait "${fixed_pids[$idx]}"; then
      fixed_results[$idx]=0
    else
      fixed_results[$idx]=1
    fi
  done

  declare -a sharegpt_pids=()
  for ((i=0; i<NPU_COUNT; i++)); do
    port=${serve_ports[$i]}
    npu=$i
    result_dir="$OUTPUT_STRESS/${model}/npu${npu}"
    mkdir -p "$result_dir"

    run_sharegpt_benchmark "$port" "$result_dir" >"$LOG_STRESS/${model}/npu${npu}/sharegpt.log" 2>&1 &
    sharegpt_pids+=($!)
  done

  # Wait for all sharegpt benchmarks to complete and report results
  for idx in "${!sharegpt_pids[@]}"; do
    npu=$idx
    sharegpt_result=0
    wait "${sharegpt_pids[$idx]}" || sharegpt_result=$?

    # Both fixed and sharegpt must pass for overall PASS
    if [ ${fixed_results[$idx]} -eq 0 ] && [ $sharegpt_result -eq 0 ]; then
      SUMMARY_DATA+=("$model|NPU $npu|Fixed+ShareGPT|PASS")
    else
      SUMMARY_DATA+=("$model|NPU $npu|Fixed+ShareGPT|FAIL")
    fi
  done

  stop_serving "${serve_pids[@]}"
done

######################################
# Summary
######################################
SUMMARY_LOG="${OUTPUT_STRESS}/PF_result.log"
HTML_REPORT="${OUTPUT_STRESS}/PF_result.html"

FAILED=0
for row in "${SUMMARY_DATA[@]}"; do
  IFS='|' read -r m n test s <<<"$row"
  [ "$s" = "FAIL" ] && FAILED=1
done

{
  echo -e "${CYAN}${BOLD}STRESS TEST SUMMARY${NC}"
  printf "%-30s | %-10s | %-20s | %-5s\n" "Model" "NPU" "Test" "Stat"

  for row in "${SUMMARY_DATA[@]}"; do
    IFS='|' read -r m n test s <<<"$row"
    printf "%-30s | %-10s | %-20s | %-5s\n" "$m" "$n" "$test" "$s"
  done

  if [ $FAILED -eq 1 ]; then
    echo -e "${RED}${BOLD}Some tests FAILED${NC}"
  else
    echo -e "${GREEN}${BOLD}All tests PASSED${NC}"
  fi
} | tee "$SUMMARY_LOG"

######################################
# HTML Report Generation
######################################
{
  cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Stress Test Report</title>
    <style>
        body { font-family: sans-serif; margin: 30px; background-color: #f4f7f6; }
        h1 { color: #2c3e50; }
        table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #34495e; color: white; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .pass { color: #27ae60; font-weight: bold; }
        .fail { color: #e74c3c; font-weight: bold; }
        .footer { margin-top: 20px; font-weight: bold; font-size: 1.2em; }
    </style>
</head>
<body>
    <h1>Furiosa Stress Test Summary</h1>
    <p><strong>Generated:</strong> $(date)</p>
    <table>
        <thead>
            <tr>
                <th>Model</th>
                <th>NPU</th>
                <th>Test</th>
                <th>Status</th>
            </tr>
        </thead>
        <tbody>
EOF

  for row in "${SUMMARY_DATA[@]}"; do
    IFS='|' read -r m n test s <<<"$row"
    status_class=$( [ "$s" = "PASS" ] && echo "pass" || echo "fail" )
    echo "            <tr><td>$m</td><td>$n</td><td>$test</td><td class=\"$status_class\">$s</td></tr>"
  done

  cat <<EOF
        </tbody>
    </table>
    <div class="footer">
        $( [ $FAILED -eq 1 ] && echo "<span class='fail'>RESULT: Some tests FAILED</span>" || echo "<span class='pass'>RESULT: All tests PASSED</span>" )
    </div>
</body>
</html>
EOF
} > "$HTML_REPORT"

echo -e "HTML report saved to: ${YELLOW}$HTML_REPORT${NC}"

if [ $FAILED -eq 1 ]; then
  exit 1
fi
