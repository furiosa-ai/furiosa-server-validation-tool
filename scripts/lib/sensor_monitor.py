#!/usr/bin/env python3
"""Per-second NPU sensor sampler.

Writes a CSV with SoC temp, HBM0/HBM1 temp, and power for every NPU that
exposes /sys/kernel/debug/rngd/mgmt<N>/sensor_readings.
"""

import argparse
import csv
import datetime
import os
import sys
import time


def monitor(output_dir, timestamp, interval):
    """Sample sensor readings every `interval` seconds and write to CSV.

    Args:
        output_dir: Directory to write the CSV file.
        timestamp: Suffix used in the CSV filename.
        interval: Sampling interval in seconds.
    """
    base_path = "/sys/kernel/debug/rngd/mgmt"
    sensor_file = "/sensor_readings"
    valid_npus = [i for i in range(8) if os.path.exists(f"{base_path}{i}{sensor_file}")]
    if not valid_npus:
        sys.exit(1)

    log_file = os.path.join(output_dir, f"sensor_log_{timestamp}.csv")
    with open(log_file, "w", newline="") as f:
        writer = csv.writer(f)
        header = ["timestamp"]
        for n in valid_npus:
            header += [
                f"npu{n}_soc_temp",
                f"npu{n}_hbm0_temp",
                f"npu{n}_hbm1_temp",
                f"npu{n}_power",
            ]
        writer.writerow(header)

        while True:
            row = [datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")]
            for n in valid_npus:
                try:
                    with open(f"{base_path}{n}{sensor_file}") as sp:
                        data = sp.read().strip().replace(",", " ").split()
                        if len(data) >= 5:
                            # data[1]: SoC, data[2]: HBM0, data[3]: HBM1, data[4]: Power
                            row += [data[1], data[2], data[3], data[4]]
                        else:
                            row += ["", "", "", ""]
                except Exception:
                    row += ["", "", "", ""]
            writer.writerow(row)
            f.flush()
            time.sleep(interval)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--timestamp", required=True)
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args()
    monitor(args.output, args.timestamp, args.interval)
