all: build

build:
	./build.sh

test: build
	./test.sh

lint: build
	./setup.sh --lint

fmt:
	./setup.sh --fmt

fmt-check:
	./setup.sh --fmt --check-only

check: fmt-check lint test

clean:
	rm -rf dist temp/*.cast dotfiles-diagnostics.json
