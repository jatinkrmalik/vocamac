# VocaMac — Makefile
# Run `make help` for available commands.

.PHONY: build install install-cli dmg release test clean run help

## Build .app bundle in repo root (fast, for development)
build:
	@./scripts/build.sh

## Build and install to /Applications (recommended for first-time setup)
install:
	@./scripts/install.sh

## Install CLI commands (vocamac, vocamac-build) to ~/.local/bin
install-cli:
	@./scripts/install.sh --cli

## Build DMG for distribution
dmg:
	@./scripts/dist.sh

## Release to GitHub + Bitbucket (usage: make release VERSION=0.3.0)
release:
	@./scripts/release.sh $(VERSION)

## Run tests
test:
	@swift test

## Remove build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@swift package clean
	@rm -rf VocaMac.app
	@rm -rf .build
	@rm -rf dist
	@echo "✅ Clean complete"

## Launch the locally built .app (build first with `make build`)
run:
	@open VocaMac.app 2>/dev/null || (echo "❌ VocaMac.app not found. Run 'make build' first." && exit 1)

## Show this help
help:
	@echo "VocaMac — Available Commands"
	@echo ""
	@echo "  make build        Build .app bundle (fast, for development)"
	@echo "  make install      Build + install to /Applications (recommended)"
	@echo "  make install-cli  Install CLI commands to ~/.local/bin"
	@echo "  make dmg          Build DMG for distribution (output in dist/)"
	@echo "  make release VERSION=X.Y.Z  Release to GitHub + Bitbucket"
	@echo "  make test         Run tests"
	@echo "  make run          Launch the locally built .app"
	@echo "  make clean        Remove build artifacts"
	@echo "  make help         Show this help"
	@echo ""
	@echo "Quick start:  make install"
