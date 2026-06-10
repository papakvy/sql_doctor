# Makefile

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
COMMAND_NAME = sql_doctor
INSTALL_PATH = $(DESTDIR)$(BINDIR)/$(COMMAND_NAME)
CARGO_TARGET_DIR ?= target
DEBUG_BINARY = $(CURDIR)/$(CARGO_TARGET_DIR)/debug/$(COMMAND_NAME)
RELEASE_BINARY = $(CURDIR)/$(CARGO_TARGET_DIR)/release/$(COMMAND_NAME)

install: build
		@install -d "$(DESTDIR)$(BINDIR)"
		@install -m 0755 "$(RELEASE_BINARY)" "$(INSTALL_PATH)"
		@echo "'sql_doctor' was installed successfully."
		@echo "Run '$(INSTALL_PATH) -h' for more information."

uninstall:
		@rm -f "$(INSTALL_PATH)"
		@echo "'sql_doctor' has been removed successfully."

build:
		@cargo build --release
		@echo "Build succeeded."

test:
		@cargo test
		@cargo build
		@SQL_DOCTOR_BIN="$(DEBUG_BINARY)" bash tests/run.sh

verify:
		@echo "Verifying sql_doctor..."
		@if "$(RELEASE_BINARY)" -v; then \
			echo "OK"; \
		else \
			echo "NG"; \
			exit 1; \
		fi
		@echo "Verification completed."

verify-install:
		@echo "Verifying installed sql_doctor..."
		@if "$(INSTALL_PATH)" -v; then \
			echo "OK"; \
		else \
			echo "NG"; \
			exit 1; \
		fi
		@echo "Verification completed."

.PHONY: install uninstall build test verify verify-install
