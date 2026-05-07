# Xcode Power - Build Targets

BINARY_NAME = XcodePower
BUILD_DIR = .build/release
INSTALL_DIR ?= /usr/local/bin

.PHONY: build clean install test

## Build the release binary (statically linked where possible)
build:
	swift build -c release --static-swift-stdlib 2>/dev/null || swift build -c release

## Run all tests
test:
	swift test

## Clean build artifacts
clean:
	swift package clean

## Install the binary to INSTALL_DIR (default: /usr/local/bin)
install: build
	install -d $(INSTALL_DIR)
	install $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)

## Print the path to the compiled binary
binary-path:
	@echo "$(BUILD_DIR)/$(BINARY_NAME)"
