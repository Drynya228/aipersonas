SHELL := /bin/bash

.PHONY: bootstrap dev lint test package

bootstrap:
	@echo "[bootstrap] Resolving Swift package dependencies"
	swift package resolve
	@echo "[bootstrap] Preparing local database directory"
	@mkdir -p .build/.agentdesk
	@touch .bootstrap-complete

lint:
	@echo "[lint] Formatting Swift sources (swift-format stub)"
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format --in-place --recursive AgentCore ToolHub Voice RAG Storage RevenueWatch Payments Compliance AgentDeskApp; \
	else \
		echo "swift-format not installed; skipping"; \
	fi

dev:
	@echo "[dev] Building AgentDesk in debug mode"
	swift build -c debug
	@echo "[dev] Launching local simulators (stub)"
	@touch .dev-last-run

test:
	@echo "[test] Running XCTest suite"
	swift test --parallel

package:
	@echo "[package] Creating release archive"
	swift build -c release
	tar -czf AgentDesk-dist.tgz .build/release
