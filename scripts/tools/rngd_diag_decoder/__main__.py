import sys
import os
import yaml
import collections

GREEN = "\033[92m"
RED   = "\033[91m"
RESET = "\033[0m"
BOLD  = "\033[1m"

def strip_ansi(text):
    return text.replace(GREEN, "").replace(RED, "").replace(RESET, "").replace(BOLD, "")

class Logger:
    """Tees stdout to a file, stripping ANSI codes from the file copy."""
    def __init__(self, filename):
        self.terminal = sys.stdout
        self.log = open(filename, "w", encoding="utf-8")

    def write(self, message):
        self.terminal.write(message)
        self.log.write(strip_ansi(message))

    def flush(self):
        self.terminal.flush()
        self.log.flush()

def generate_html_report(all_results, filename):
    npu_groups = collections.defaultdict(list)
    for npu_id, item, res_text in all_results:
        npu_groups[npu_id].append((item, res_text))

    html = """
    <html>
    <head>
        <meta charset="utf-8">
        <style>
            body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 40px; color: #333; }
            .npu-section { margin-bottom: 50px; }
            .npu-title { background-color: #2c3e50; color: white; padding: 10px 20px; border-radius: 5px 5px 0 0; display: inline-block; min-width: 150px; font-weight: bold; }
            table { width: 100%; border-collapse: collapse; margin-top: 0; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
            th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
            th { background-color: #f8f9fa; color: #555; font-weight: bold; width: 25%; }
            tr:nth-child(even) { background-color: #fdfdfd; }
            .pass { color: #27ae60; font-weight: bold; }
            .fail { color: #e74c3c; font-weight: bold; }
            h1 { border-bottom: 2px solid #eee; padding-bottom: 10px; }
        </style>
    </head>
    <body>
        <h1>Furiosa HW Component Health Check Report</h1>
    """

    for npu_id in sorted(npu_groups.keys()):
        html += f"""
        <div class="npu-section">
            <div class="npu-title">{npu_id.upper()} Status</div>
            <table>
                <thead><tr><th>ITEM</th><th>RESULT</th></tr></thead>
                <tbody>
        """
        for item, res_text in npu_groups[npu_id]:
            res_class = "pass" if "PASS" in res_text else "fail"
            html += f"""
                    <tr>
                        <td>{item}</td>
                        <td class="{res_class}">{strip_ansi(res_text)}</td>
                    </tr>
            """
        html += """
                </tbody>
            </table>
        </div>
        """

    html += """
    </body>
    </html>
    """

    with open(filename, "w", encoding="utf-8") as f:
        f.write(html)

def check_npu_status(npu_id, diag_data, bench_data, stress_data):
    results = {}

    sensors = diag_data.get('sensor', {}).get('details', {})
    limits = {
        'ta': (10.0, 80.0), 'npu_ambient': (10.0, 80.0), 'hbm': (10.0, 80.0),
        'soc': (10.0, 80.0), 'pe': (10.0, 80.0), 'p_rms_total': (30.0, 60.0),
    }
    sensor_vals = [
        f"Ta:{sensors.get('ta')}", f"Amb:{sensors.get('npu_ambient')}",
        f"SOC:{sensors.get('soc')}", f"PWR:{sensors.get('p_rms_total')}",
    ]
    s_errors = [f"{k}:{v}" for k, v in sensors.items()
                if k in limits and not (limits[k][0] <= v <= limits[k][1])]
    results['SENSORS'] = (
        f"{GREEN}PASS{RESET} ({', '.join(sensor_vals)})"
        if not s_errors else
        f"{RED}FAIL{RESET} ({', '.join(s_errors)})"
    )

    p_val = diag_data.get('power_sense', {}).get('value')
    results['PWR_SENSE'] = (
        f"{GREEN}PASS{RESET}" if p_val in [2.0, 3.0] else f"{RED}FAIL{RESET} (Val:{p_val})"
    )

    pcie = diag_data.get('pcie', {})
    link = pcie.get('link', {})
    speed = link.get('speed', 'N/A')
    width = link.get('width', 'N/A')
    aer   = pcie.get('aer', {}).get('total_err_fatal', 0)
    results['PCIE'] = (
        f"{GREEN}PASS{RESET} ({speed}, {width})"
        if speed == "32GT/s" and width == "x16" and aer == 0 else
        f"{RED}FAIL{RESET} (AER:{aer})"
    )

    for mode in ['read', 'write']:
        m_data = bench_data.get(mode, {}).get(npu_id, {})
        label = f"hal-bench ({mode.upper()})"
        if 'error' in m_data:
            results[label] = f"{RED}FAIL{RESET} (Busy/Error)"
        elif 'thrpt_gibs' in m_data:
            avgs = [str(round(sum(g)/len(g), 2)) for g in m_data['thrpt_gibs'] if g]
            results[label] = f"{GREEN}PASS{RESET} ({', '.join(avgs)})"
        else:
            results[label] = "NO_DATA"

    st = stress_data.get(npu_id, {})
    results['STRESS_TEST'] = (
        f"{GREEN}PASS{RESET} (QPS:{st.get('qps')})"
        if st.get('exit_code') == 0 else
        f"{RED}FAIL{RESET} (Exit:{st.get('exit_code')})"
    )

    return results

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 rngd-diag_decoder.py <yaml_file> [output_dir]")
        sys.exit(1)

    input_yaml = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "."

    log_filename  = os.path.join(output_dir, "PF_result.log")
    html_filename = os.path.join(output_dir, "PF_result.html")

    sys.stdout = Logger(log_filename)

    try:
        with open(input_yaml, 'r') as f:
            raw = yaml.safe_load(f)
    except Exception as e:
        print(f"Error opening/reading YAML: {e}")
        sys.exit(1)

    root   = raw.get('rngd_diag', {}).get('npus', {})
    bench  = raw.get('furiosa_hal_bench', {})
    stress = raw.get('furiosa_stress_test', {}).get('full', {})

    print("\n" + BOLD + "="*80 + RESET)
    print(BOLD + " Furiosa HW Component Health Check" + RESET)
    print(BOLD + "="*80 + RESET)
    print(f"{BOLD}{'NPU ID':<10} | {'ITEM':<15} | {'RESULT'}{RESET}")
    print("-" * 80)

    html_data = []
    for npu_id in sorted(root.keys()):
        report = check_npu_status(npu_id, root[npu_id], bench, stress)
        for item, res in report.items():
            print(f"{npu_id:<10} | {item:<15} | {res}")
            html_data.append((npu_id, item, res))
        print("-" * 80)

    generate_html_report(html_data, html_filename)
    sys.stdout.flush()

if __name__ == "__main__":
    main()
