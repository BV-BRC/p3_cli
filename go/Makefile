# BV-BRC CLI - Go Implementation
#
# Build system for the Go port of the BV-BRC command-line interface.

# Variables
GO ?= go
GOOS ?= $(shell $(GO) env GOOS 2>/dev/null || echo linux)
GOARCH ?= $(shell $(GO) env GOARCH 2>/dev/null || echo amd64)
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
BUILD_TIME ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

LDFLAGS := -ldflags "-X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)"

# Output directory
BIN_DIR := bin

# Find all commands (directories under cmd/)
COMMANDS := $(notdir $(wildcard cmd/*))

# Default target
.PHONY: all
all: build

# Build all commands
.PHONY: build
build: $(COMMANDS)

# Build individual commands
.PHONY: $(COMMANDS)
$(COMMANDS):
	@mkdir -p $(BIN_DIR)
	$(GO) build $(LDFLAGS) -o $(BIN_DIR)/$@ ./cmd/$@

# Run tests
.PHONY: test
test:
	$(GO) test -v ./...

# Run tests with coverage
.PHONY: test-coverage
test-coverage:
	$(GO) test -v -coverprofile=coverage.out ./...
	$(GO) tool cover -html=coverage.out -o coverage.html

# Format code
.PHONY: fmt
fmt:
	$(GO) fmt ./...

# Lint code
.PHONY: lint
lint:
	$(GO) vet ./...

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BIN_DIR)
	rm -f coverage.out coverage.html

# Download dependencies
.PHONY: deps
deps:
	$(GO) mod download
	$(GO) mod tidy

# Cross-compilation targets
.PHONY: build-linux
build-linux:
	GOOS=linux GOARCH=amd64 $(MAKE) build
	@for cmd in $(COMMANDS); do mv $(BIN_DIR)/$$cmd $(BIN_DIR)/$$cmd-linux-amd64 2>/dev/null || true; done

.PHONY: build-darwin
build-darwin:
	GOOS=darwin GOARCH=amd64 $(MAKE) build
	@for cmd in $(COMMANDS); do mv $(BIN_DIR)/$$cmd $(BIN_DIR)/$$cmd-darwin-amd64 2>/dev/null || true; done
	GOOS=darwin GOARCH=arm64 $(MAKE) build
	@for cmd in $(COMMANDS); do mv $(BIN_DIR)/$$cmd $(BIN_DIR)/$$cmd-darwin-arm64 2>/dev/null || true; done

.PHONY: build-windows
build-windows:
	GOOS=windows GOARCH=amd64 $(MAKE) build
	@for cmd in $(COMMANDS); do mv $(BIN_DIR)/$$cmd $(BIN_DIR)/$$cmd-windows-amd64.exe 2>/dev/null || true; done

.PHONY: build-all
build-all: build-linux build-darwin build-windows

# Install to system
.PHONY: install
install: build
	@echo "Installing to $(GOPATH)/bin..."
	@for cmd in $(COMMANDS); do \
		cp $(BIN_DIR)/$$cmd $(GOPATH)/bin/$$cmd; \
	done

# Development helpers
.PHONY: run-example
run-example: p3-all-genomes
	./$(BIN_DIR)/p3-all-genomes --limit 5 -a genome_id -a genome_name

# Show help
.PHONY: help
help:
	@echo "BV-BRC CLI - Go Implementation"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build all commands (default)"
	@echo "  build        Build all commands"
	@echo "  test         Run tests"
	@echo "  test-coverage Run tests with coverage report"
	@echo "  fmt          Format code"
	@echo "  lint         Lint code"
	@echo "  clean        Remove build artifacts"
	@echo "  deps         Download and tidy dependencies"
	@echo "  build-linux  Build for Linux"
	@echo "  build-darwin Build for macOS (amd64 and arm64)"
	@echo "  build-windows Build for Windows"
	@echo "  build-all    Build for all platforms"
	@echo "  install      Install to GOPATH/bin"
	@echo "  help         Show this help"
	@echo ""
	@echo "Commands:"
	@for cmd in $(COMMANDS); do echo "  $$cmd"; done
