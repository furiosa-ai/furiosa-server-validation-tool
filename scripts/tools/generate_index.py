#!/usr/bin/env python3
"""Generate a run-level index.html and summary.json from per-phase outputs."""

import argparse
import datetime
import json
import pathlib
import socket

PHASES = ["diag", "p2p", "stress"]


def read_dmi(path):
    """Read a one-line DMI string from sysfs, returning "Unknown" on failure."""
    try:
        return pathlib.Path(path).read_text().strip()
    except Exception:
        return "Unknown"


def read_exit_code(phase_dir):
    """Read the integer exit code recorded in `<phase_dir>/exit_code.txt`.

    Returns:
        The integer exit code, or None if the file is missing or unreadable.
    """
    f = phase_dir / "exit_code.txt"
    if not f.exists():
        return None
    try:
        return int(f.read_text().strip())
    except ValueError:
        return None


def status_label(exit_code):
    """Map an exit code to its status label ("pass", "fail", or "unknown")."""
    if exit_code is None:
        return "unknown"
    return "pass" if exit_code == 0 else "fail"


def discover_phases(run_dir):
    """Scan `run_dir` for phase output directories and collect their metadata.

    Returns:
        A list of dicts with `phase`, `report` (relative path or None), and
        `exit_code` keys, in PHASES order.
    """
    found = []
    for phase in PHASES:
        phase_dir = run_dir / phase
        if not phase_dir.is_dir():
            continue
        report = phase_dir / "PF_result.html"
        rel_report = report.relative_to(run_dir) if report.exists() else None
        found.append({
            "phase": phase,
            "report": rel_report,
            "exit_code": read_exit_code(phase_dir),
        })
    return found


def render_html(run_dir, phases, hostname, vendor, model, generated_at):
    """Render the run-level index.html as a string."""
    lines = [
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        '    <meta charset="utf-8">',
        "    <title>Furiosa RNGD Validator Run Report</title>",
        "    <style>",
        "        body {",
        "            font-family: sans-serif;",
        "            margin: 30px;",
        "            background-color: #f4f7f6;",
        "            color: #333;",
        "        }",
        "        h1, h2 { color: #2c3e50; }",
        "        .meta {",
        "            background: white;",
        "            padding: 16px;",
        "            border-radius: 6px;",
        "            box-shadow: 0 2px 4px rgba(0,0,0,0.05);",
        "            margin-bottom: 24px;",
        "        }",
        "        .meta dt { font-weight: bold; }",
        "        .meta dd { margin: 0 0 8px 0; }",
        "        ul.phases { list-style: none; padding: 0; }",
        "        ul.phases li {",
        "            background: white;",
        "            padding: 12px 16px;",
        "            border-radius: 6px;",
        "            margin-bottom: 8px;",
        "            box-shadow: 0 2px 4px rgba(0,0,0,0.05);",
        "            display: flex;",
        "            justify-content: space-between;",
        "        }",
        "        ul.phases a { color: #2c3e50; font-weight: bold; text-decoration: none; }",
        "        ul.phases a:hover { text-decoration: underline; }",
        "        .pass { color: #27ae60; font-weight: bold; }",
        "        .fail { color: #e74c3c; font-weight: bold; }",
        "        .unknown { color: #7f8c8d; font-weight: bold; }",
        "    </style>",
        "</head>",
        "<body>",
        "    <h1>Furiosa RNGD Validator Run Report</h1>",
        '    <div class="meta">',
        "        <dl>",
        f"            <dt>Hostname</dt><dd>{hostname}</dd>",
        f"            <dt>Vendor</dt><dd>{vendor}</dd>",
        f"            <dt>Model</dt><dd>{model}</dd>",
        f"            <dt>Generated</dt><dd>{generated_at}</dd>",
        f"            <dt>Run directory</dt><dd>{run_dir}</dd>",
        "        </dl>",
        "    </div>",
        "    <h2>Phase reports</h2>",
        '    <ul class="phases">',
    ]
    if not phases:
        lines.append("        <li>No phase reports found.</li>")
    else:
        for entry in phases:
            status = status_label(entry["exit_code"])
            link = (
                f'<a href="{entry["report"]}">{entry["phase"]}</a>'
                if entry["report"]
                else entry["phase"]
            )
            lines.append(f'        <li>{link}<span class="{status}">{status.upper()}</span></li>')
    lines += [
        "    </ul>",
        "</body>",
        "</html>",
        "",
    ]
    return "\n".join(lines)


def main():
    """Write index.html and summary.json under the directory given by --run-dir."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=pathlib.Path)
    args = parser.parse_args()

    run_dir = args.run_dir.resolve()
    if not run_dir.is_dir():
        raise SystemExit(f"run-dir does not exist: {run_dir}")

    phases = discover_phases(run_dir)
    hostname = socket.gethostname()
    vendor = read_dmi("/sys/class/dmi/id/sys_vendor")
    model = read_dmi("/sys/class/dmi/id/product_name")
    generated_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    html = render_html(
        run_dir=run_dir,
        phases=phases,
        hostname=hostname,
        vendor=vendor,
        model=model,
        generated_at=generated_at,
    )
    index_path = run_dir / "index.html"
    index_path.write_text(html)
    print(f"Wrote {index_path}")

    overall = "pass"
    for entry in phases:
        st = status_label(entry["exit_code"])
        if st == "fail":
            overall = "fail"
            break
        if st == "unknown" and overall == "pass":
            overall = "unknown"

    summary = {
        "hostname": hostname,
        "vendor": vendor,
        "model": model,
        "generated_at": generated_at,
        "run_dir": str(run_dir),
        "overall_status": overall,
        "phases": [
            {
                "phase": e["phase"],
                "exit_code": e["exit_code"],
                "status": status_label(e["exit_code"]),
                "report": str(e["report"]) if e["report"] else None,
            }
            for e in phases
        ],
    }
    summary_path = run_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
