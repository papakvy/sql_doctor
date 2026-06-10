# Makefile

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
COMMAND_NAME = sql_doctor
SCRIPT_NAME = sql_doctor
INSTALL_PATH = $(DESTDIR)$(BINDIR)/$(COMMAND_NAME)

install:
		@install -d "$(DESTDIR)$(BINDIR)"
		@install -m 0755 "$(SCRIPT_NAME)" "$(INSTALL_PATH)"
		@echo "'sql_doctor' was installed successfully."
		@echo "Run '$(INSTALL_PATH) -h' for more information."

uninstall:
		@rm -f "$(INSTALL_PATH)"
		@echo "'sql_doctor' has been removed successfully."

build:
		@bash -n "$(SCRIPT_NAME)"
		@echo "Build succeeded."

test:
		@bash tests/run.sh

verify:
		@echo "Verifying sql_doctor..."
		@if "./$(SCRIPT_NAME)" -v; then \
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
