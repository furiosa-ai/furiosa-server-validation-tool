#!/bin/bash
set -euo pipefail

OUTPUT_P2P=${OUTPUT_P2P:-$OUTPUT_DIR/p2p_$TIMESTAMP}
mkdir -p "$OUTPUT_P2P"
LOG_FILE="${OUTPUT_P2P}/PF_result.log"
HTML_FILE="${OUTPUT_P2P}/PF_result.html"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

init_html() {
    cat <<EOF > "$HTML_FILE"
<html>
<head>
    <meta charset="utf-8">
    <style>
        body { font-family: sans-serif; margin: 30px; background-color: #f4f7f6; }
        h1, h2 { color: #2c3e50; }
        .section { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 30px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #34495e; color: white; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .val-text { color: #27ae60; font-weight: bold; }
        .status-warn { color: #f39c12; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Furiosa P2P Benchmark Report</h1>
    <p><strong>Generated:</strong> $(date)</p>
EOF
}

append_html_section() {
    local label=$1
    shift
    local data=("$@")

    cat <<EOF >> "$HTML_FILE"
    <div class="section">
        <h2>>>> Benchmark Summary: $label</h2>
        <table>
            <tr>
                <th>Time</th>
                <th>P2P Path</th>
                <th>Latency (ms)</th>
                <th>Throughput (GiB/s)</th>
                <th>Pass/Fail</th>
            </tr>
EOF
    for entry in "${data[@]}"; do
        IFS='|' read -r r_time r_path r_lat r_thr <<< "$entry"
        echo "<tr><td>$r_time</td><td>$r_path</td><td class='val-text'>$r_lat</td><td class='val-text'>$r_thr</td><td class='status-warn'>[Contact Furiosa Support]</td></tr>" >> "$HTML_FILE"
    done
    echo "</table></div>" >> "$HTML_FILE"
}

NPU_COUNT=$(find /sys/kernel/debug/rngd/ -maxdepth 1 -name "mgmt*" 2>/dev/null | wc -l)
[ "$NPU_COUNT" -eq 0 ] && { echo -e "${RED}Error: No NPUs found${NC}"; exit 1; }

save_lspci_info() {
    local label=$1
    echo -e "${BLUE}[$(date +%T)] Saving lspci info for: $label${NC}" | tee -a "$LOG_FILE"
    lspci -tv  > "${OUTPUT_P2P}/lspci-topology_${label}.log" || echo "lspci -tv failed"  >> "$LOG_FILE"
    lspci -vvv > "${OUTPUT_P2P}/lspci-vvv_${label}.log"      || echo "lspci -vvv failed" >> "$LOG_FILE"
}

run_p2p_benchmark() {
    local label=$1
    declare -a SUMMARY_DATA

    echo -e "${CYAN}${BOLD}\n>>> Starting Benchmark: $label <<<\n${NC}" | tee -a "$LOG_FILE"

    for (( i=0; i<NPU_COUNT; i++ )); do
        for (( j=0; j<NPU_COUNT; j++ )); do
            [ "$i" -eq "$j" ] && continue

            local CURRENT_TIME
            CURRENT_TIME=$(date +%T)

            local STEP_LOG
            STEP_LOG=$(mktemp "${OUTPUT_P2P}/step_p2p_XXXX.tmp")

            echo -e "${BOLD}--------------------------------------------------${NC}" | tee -a "$LOG_FILE"
            echo -e "[$CURRENT_TIME] Testing P2P ($label): ${GREEN}Source $i${NC} -> ${GREEN}Destination $j${NC}" | tee -a "$LOG_FILE"
            echo -e "${BOLD}--------------------------------------------------${NC}" | tee -a "$LOG_FILE"

            furiosa-hal-bench p2p \
                --npu "$i" \
                --dst-npu "$j" \
                --buffer-size 16MiB \
                2>&1 | tee "$STEP_LOG"

            cat "$STEP_LOG" >> "$LOG_FILE"

            CLEAN_OUT=$(sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" "$STEP_LOG")

            LAT=$(echo "$CLEAN_OUT" | grep "time:"  | head -n 1 | grep -o "\[.*\]" || true)
            THR=$(echo "$CLEAN_OUT" | grep "thrpt:" | head -n 1 | grep -o "\[.*\]" || true)

            LAT=${LAT:-"[N/A]"}
            THR=${THR:-"[N/A]"}

            SUMMARY_DATA+=("$CURRENT_TIME|Src $i->Dst $j|$LAT|$THR")

            rm -f "$STEP_LOG"
            echo >> "$LOG_FILE"
        done
    done

    {
        echo
        echo -e "${CYAN}======================================================================================================================================================${NC}"
        echo -e "${CYAN}${BOLD}                                            P2P BENCHMARK SUMMARY REPORT ($label)${NC}"
        echo -e "${CYAN}======================================================================================================================================================${NC}"
        printf "${BOLD}%-10s | %-15s | %-40s | %-40s | %-25s${NC}\n" \
            "Time" "P2P Path" "Latency (ms)" "Throughput (GiB/s)" "PASS/FAIL"
        echo -e "${CYAN}------------------------------------------------------------------------------------------------------------------------------------------------------${NC}"

        for entry in "${SUMMARY_DATA[@]}"; do
            IFS='|' read -r r_time r_path r_lat r_thr <<< "$entry"
            printf "%-10s | %-15s | ${GREEN}%-40s${NC} | ${GREEN}%-40s${NC} | ${YELLOW}%-25s${NC}\n" \
                "$r_time" "$r_path" "$r_lat" "$r_thr" "[Contact Furiosa Support]"
        done

        echo -e "${CYAN}======================================================================================================================================================${NC}"
    } | tee -a "$LOG_FILE"

    append_html_section "$label" "${SUMMARY_DATA[@]}"
}

init_html

echo -e "${BOLD}All results will be saved in: ${YELLOW}$OUTPUT_P2P${NC}" | tee -a "$LOG_FILE"

ACS_DISABLED=0
restore_acs() {
    if [ "$ACS_DISABLED" = "1" ]; then
        echo -e "\n${YELLOW}[cleanup] Restoring ACS to enabled state...${NC}" | tee -a "$LOG_FILE" || true
        bash "ACS_enable.sh" 2>&1 | tee -a "$LOG_FILE" || true
    fi
}
trap restore_acs EXIT INT TERM

echo -e "\n${BOLD}[STEP 1] ACS Disable Sequence${NC}" | tee -a "$LOG_FILE"
bash "ACS_disable.sh" 2>&1 | tee -a "$LOG_FILE"
ACS_DISABLED=1
save_lspci_info "ACS_Disabled"
run_p2p_benchmark "after ACS disable"

echo >> "$LOG_FILE"

echo -e "\n${BOLD}[STEP 2] ACS Enable Sequence${NC}" | tee -a "$LOG_FILE"
bash "ACS_enable.sh" 2>&1 | tee -a "$LOG_FILE"
ACS_DISABLED=0
save_lspci_info "ACS_Enabled"
run_p2p_benchmark "after ACS enable"

echo "</body></html>" >> "$HTML_FILE"

sudo dmesg > "${OUTPUT_P2P}/dmesg_$TIMESTAMP.log"

echo -e "\n${GREEN}${BOLD}==========================================================================${NC}"
echo -e "${GREEN}${BOLD}  Test Completed Successfully!${NC}"
echo -e "${BOLD}  All logs and reports are in: ${YELLOW}$OUTPUT_P2P${NC}"
echo -e "${GREEN}${BOLD}==========================================================================${NC}"
