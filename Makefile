VERSION ?= 2026.1.0
IMAGE := furiosa-rngd-validator:$(VERSION)
RUN_TESTS ?= diag,p2p,stress

SHELL_SCRIPTS := \
	entrypoint.sh \
	scripts/lib/acs.sh \
	scripts/lib/common.sh \
	scripts/lib/html.sh \
	scripts/phases/run_diag.sh \
	scripts/phases/run_p2p.sh \
	scripts/phases/run_stress.sh

# Build the Docker image.
.PHONY: build
build:
	docker build --progress=plain -t $(IMAGE) .

# Run the container with privileged + debugfs mounts. Requires HF_TOKEN.
.PHONY: run
run:
	@if [ -z "$$HF_TOKEN" ]; then echo "ERROR: HF_TOKEN not set"; exit 1; fi
	docker run --rm -it --privileged \
	    -v /sys/kernel/debug:/sys/kernel/debug \
	    -v /lib/modules:/lib/modules:ro \
	    -v $(CURDIR)/outputs:/root/furiosa-server-validation-tool/outputs \
	    -e HF_TOKEN \
	    -e RUN_TESTS=$(RUN_TESTS) \
	    $(IMAGE)

# Run all linters.
.PHONY: lint
lint: lint-sh lint-py

# Lint shell scripts.
.PHONY: lint-sh
lint-sh:
	# --external-sources lets shellcheck follow `# shellcheck source=...`
	# directives; --source-path=SCRIPTDIR resolves them relative to each
	# script's directory rather than the cwd shellcheck was invoked from.
	shellcheck --external-sources --source-path=SCRIPTDIR $(SHELL_SCRIPTS)
	# --indent 2 + --case-indent approximates the Google Shell Style Guide.
	# --diff exits non-zero on drift instead of rewriting in place.
	shfmt --indent 2 --case-indent --diff $(SHELL_SCRIPTS)

# Lint Python sources.
.PHONY: lint-py
lint-py:
	ruff check scripts/lib/sensor_monitor.py scripts/tools tests
	mypy

# Run the test suite.
.PHONY: test
test:
	pytest tests/

# Remove generated artifacts and tool caches.
.PHONY: clean
clean:
	rm -rf outputs/ .pytest_cache/ .mypy_cache/ .ruff_cache/
	find . -type d -name __pycache__ -exec rm -rf {} +
