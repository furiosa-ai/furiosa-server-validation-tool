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
    return {
        "sensor": {"details": sensors or {}},
        "power_sense": {"value": power},
        "pcie": {"link": {"speed": speed, "width": width}, "aer": {"total_err_fatal": aer}},
    }


# SENSORS row should PASS when all readings sit inside SENSOR_LIMITS bounds
# and FAIL when any reading falls outside its (lo, hi) interval.
@pytest.mark.parametrize(
    "sensors, expected",
    [
        ({"ta": 50.0, "soc": 60.0}, "PASS"),
        ({"soc": 95.0}, "FAIL"),
    ],
)
def test_sensors(sensors, expected):
    result = decoder_cli.check_npu_status("npu0", make_diag(sensors=sensors), {}, {})
    assert expected in render.strip_ansi(result["SENSORS"])


# PWR_SENSE row should PASS only for power_sense.value in
# POWER_SENSE_VALID_VALUES; everything else (including missing data) should FAIL.
@pytest.mark.parametrize(
    "power, expected",
    [(2.0, "PASS"), (3.0, "PASS"), (1.0, "FAIL"), (None, "FAIL")],
)
def test_pwr_sense(power, expected):
    result = decoder_cli.check_npu_status("npu0", make_diag(power=power), {}, {})
    assert expected in render.strip_ansi(result["PWR_SENSE"])


# PCIE row should PASS only when link speed and width match expected values
# and total_err_fatal is zero; any AER fatal count should flip it to FAIL.
@pytest.mark.parametrize(
    "speed, width, aer, expected",
    [
        (thresholds.PCIE_EXPECTED_SPEED, thresholds.PCIE_EXPECTED_WIDTH, 0, "PASS"),
        (thresholds.PCIE_EXPECTED_SPEED, thresholds.PCIE_EXPECTED_WIDTH, 3, "FAIL"),
    ],
)
def test_pcie(speed, width, aer, expected):
    result = decoder_cli.check_npu_status(
        "npu0", make_diag(speed=speed, width=width, aer=aer), {}, {}
    )
    assert expected in render.strip_ansi(result["PCIE"])


# generate_html_report should write a file containing the NPU id, derive the
# per-row .pass / .fail CSS class from the result text, and strip raw ANSI
# escape sequences before writing.
def test_generate_html_report_smoke(tmp_path):
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
