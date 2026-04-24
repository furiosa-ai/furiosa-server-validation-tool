"""HTML rendering, terminal logger, and ANSI color constants."""

import sys
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
