"""Thresholds and expected hardware values used by check_npu_status."""

SENSOR_LIMITS = {
    "ta": (10.0, 80.0),
    "npu_ambient": (10.0, 80.0),
    "hbm": (10.0, 80.0),
    "soc": (10.0, 80.0),
    "pe": (10.0, 80.0),
    "p_rms_total": (30.0, 60.0),
}

POWER_SENSE_VALID_VALUES = (2.0, 3.0)

PCIE_EXPECTED_SPEED = "32GT/s"
PCIE_EXPECTED_WIDTH = "x16"
PCIE_EXPECTED_AER_FATAL = 0
