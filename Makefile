# Thin wrappers: paths here contain spaces, so all logic lives in quoted scripts.
.PHONY: build test fixtures bench install uninstall lint

build:
	@bash scripts/build.sh

test:
	@bash scripts/test.sh

fixtures:
	@bash scripts/fixtures.sh

bench:
	@bash scripts/bench.sh

install:
	@bash scripts/install.sh

uninstall:
	@bash scripts/uninstall.sh

lint:
	@bash scripts/lint.sh
