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

.PHONY: build
build:
	docker build --progress=plain -t $(IMAGE) .

.PHONY: run
run:
	@if [ -z "$$HF_TOKEN" ]; then echo "ERROR: HF_TOKEN not set"; exit 1; fi
	docker run --rm -it --privileged \
	    -v /sys/kernel/debug:/sys/kernel/debug \
	    -v /lib/modules:/lib/modules:ro \
	    -v $(PWD)/outputs:/root/furiosa-server-validation-tool/outputs \
	    -e HF_TOKEN=$(HF_TOKEN) \
	    -e RUN_TESTS=$(RUN_TESTS) \
	    $(IMAGE)

.PHONY: lint
lint: lint-sh lint-py lint-docker lint-yaml

.PHONY: lint-sh
lint-sh:
	shellcheck $(SHELL_SCRIPTS)
	# -i 2: 2-space indent. -ci: indent case branches. -d: diff mode,
	# exits non-zero on drift. Approximates the Google Shell Style Guide.
	shfmt -i 2 -ci -d $(SHELL_SCRIPTS)

.PHONY: lint-py
lint-py:
	ruff check scripts/lib/sensor_monitor.py scripts/tools tests
	mypy

.PHONY: lint-docker
lint-docker:
	# --failure-threshold error makes hadolint fail only on errors;
	# warnings and info stay informational.
	hadolint --failure-threshold error Dockerfile
	# --check makes dockerfmt exit non-zero on drift; --newline keeps
	# a POSIX trailing newline.
	dockerfmt --check --newline Dockerfile

.PHONY: lint-yaml
lint-yaml:
	yamllint --strict .github/
	yamlfmt -lint .github/

.PHONY: test
test: test-py test-sh

.PHONY: test-py
test-py:
	pytest tests/

.PHONY: test-sh
test-sh:
	bats tests/

.PHONY: clean
clean:
	rm -rf outputs/ .pytest_cache/ .mypy_cache/ .ruff_cache/
	find . -type d -name __pycache__ -exec rm -rf {} +
