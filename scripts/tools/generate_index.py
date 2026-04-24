#!/usr/bin/env python3
"""Generate a run-level index.html that links each phase's PF_result.html."""

import argparse
import datetime
import pathlib
import socket

PHASES = ["diag", "p2p", "stress"]


def read_dmi(path):
    try:
        return pathlib.Path(path).read_text().strip()
    except Exception:
        return "Unknown"


def discover_phase_reports(run_dir):
    found = []
    for phase in PHASES:
        report = run_dir / phase / "PF_result.html"
        if report.exists():
            found.append((phase, report.relative_to(run_dir)))
    return found


def render(run_dir, phase_reports, hostname, vendor, model, generated_at):
    lines = [
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        '    <meta charset="utf-8">',
        "    <title>Furiosa Validation Run Report</title>",
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
        "        }",
        "        ul.phases a { color: #2c3e50; font-weight: bold; text-decoration: none; }",
        "        ul.phases a:hover { text-decoration: underline; }",
        "    </style>",
        "</head>",
        "<body>",
        "    <h1>Furiosa Validation Run Report</h1>",
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
    if not phase_reports:
        lines.append("        <li>No phase reports found.</li>")
    else:
        for phase, rel in phase_reports:
            lines.append(f'        <li><a href="{rel}">{phase}</a></li>')
    lines += [
        "    </ul>",
        "</body>",
        "</html>",
        "",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=pathlib.Path)
    args = parser.parse_args()

    run_dir = args.run_dir.resolve()
    if not run_dir.is_dir():
        raise SystemExit(f"run-dir does not exist: {run_dir}")

    html = render(
        run_dir=run_dir,
        phase_reports=discover_phase_reports(run_dir),
        hostname=socket.gethostname(),
        vendor=read_dmi("/sys/class/dmi/id/sys_vendor"),
        model=read_dmi("/sys/class/dmi/id/product_name"),
        generated_at=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    )

    index_path = run_dir / "index.html"
    index_path.write_text(html)
    print(f"Wrote {index_path}")


if __name__ == "__main__":
    main()
