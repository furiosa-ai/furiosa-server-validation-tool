"""Unit tests for the rngd_diag_decoder package."""

import pytest
from rngd_diag_decoder import __main__ as decoder_cli
from rngd_diag_decoder import render, thresholds


def make_diag(
    sensors=None,
    power=2.0,
    speed=thresholds.PCIE_EXPECTED_SPEED,
    width=thresholds.PCIE_EXPECTED_WIDTH,
    aer=0,
):
    """Build a minimal rngd-diag input for check_npu_status in tests."""
    return {
        "sensor": {"details": sensors or {}},
        "power_sense": {"value": power},
        "pcie": {"link": {"speed": speed, "width": width}, "aer": {"total_err_fatal": aer}},
    }


@pytest.mark.parametrize(
    "sensors, expected",
    [
        ({"ta": 50.0, "soc": 60.0}, "PASS"),
        ({"soc": 95.0}, "FAIL"),
    ],
)
def test_sensors(sensors, expected):
    """SENSORS row should PASS when all readings sit inside SENSOR_LIMITS bounds.

    Any reading outside its (lo, hi) interval should flip the row to FAIL.
    """
    result = decoder_cli.check_npu_status("npu0", make_diag(sensors=sensors), {}, {})
    assert expected in render.strip_ansi(result["SENSORS"])


@pytest.mark.parametrize(
    "power, expected",
    [(2.0, "PASS"), (3.0, "PASS"), (1.0, "FAIL"), (None, "FAIL")],
)
def test_pwr_sense(power, expected):
    """PWR_SENSE row should PASS only for power_sense.value in POWER_SENSE_VALID_VALUES.

    Everything else (including missing data) should FAIL.
    """
    result = decoder_cli.check_npu_status("npu0", make_diag(power=power), {}, {})
    assert expected in render.strip_ansi(result["PWR_SENSE"])


@pytest.mark.parametrize(
    "speed, width, aer, expected",
    [
        (thresholds.PCIE_EXPECTED_SPEED, thresholds.PCIE_EXPECTED_WIDTH, 0, "PASS"),
        (thresholds.PCIE_EXPECTED_SPEED, thresholds.PCIE_EXPECTED_WIDTH, 3, "FAIL"),
    ],
)
def test_pcie(speed, width, aer, expected):
    """PCIE row should PASS only when link speed and width match expected values.

    Any AER fatal count should flip it to FAIL.
    """
    result = decoder_cli.check_npu_status(
        "npu0", make_diag(speed=speed, width=width, aer=aer), {}, {},
    )
    assert expected in render.strip_ansi(result["PCIE"])


def test_generate_html_report_smoke(tmp_path):
    """generate_html_report should write a file containing the NPU id.

    The per-row .pass / .fail CSS class should be derived from the result
    text, and raw ANSI escape sequences should be stripped before writing.
    """
    out = tmp_path / "report.html"
    render.generate_html_report(
        [
            ("npu0", "SENSORS", f"{render.GREEN}PASS{render.RESET}"),
            ("npu0", "PCIE", f"{render.RED}FAIL{render.RESET}"),
        ],
        str(out),
    )
    content = out.read_text()
    assert "NPU0" in content
    assert 'class="pass"' in content
    assert 'class="fail"' in content
    assert "\033[92m" not in content
