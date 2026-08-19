.PHONY: all build test lint fmt fmt-check check clean

all: build

build:
	./build.sh

test: build
	./test.sh

lint: build
	./rigrc.sh --lint

fmt:
	./rigrc.sh --fmt

fmt-check:
	./rigrc.sh --fmt --check-only

check: fmt-check lint test

clean:
	rm -rf dist temp/*.cast dotfiles-diagnostics.json
