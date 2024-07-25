# Makefile

INSTALL_DIR = /usr/local/bin
COMMAND_NAME = sql_doctor
SCRIPT_NAME = sql_doctor.sh
COMPILED_SCRIPT_NAME = $(SCRIPT_NAME).x
SHC_COMMAND = shc

install: compile
		@cp $(COMPILED_SCRIPT_NAME) $(INSTALL_DIR)/$(COMMAND_NAME)
		@chmod +x $(INSTALL_DIR)/$(COMMAND_NAME)
		@echo "'sql_doctor' was installed successfully."
		@echo "Run 'sql_doctor -h' for more information."

uninstall:
		@rm -f $(INSTALL_DIR)/$(COMMAND_NAME)
		@rm -f $(INSTALL_DIR)/$(COMPILED_SCRIPT_NAME)
		@echo "'sql_doctor' has been removed successfully."

compile: check_shc
		@$(SHC_COMMAND) -f $(SCRIPT_NAME)

check_shc:
		@command -v $(SHC_COMMAND) > /dev/null 2>&1 || { \
				echo "Error: 'shc' is not installed. Please install it first.\n"; \
				exit 1; \
		}

build: compile
		@echo "Build succeeded."

verify:
		@echo "Verifying sql_doctor..."
		@if sql_doctor -v; then \
			echo "OK"; \
		else \
			echo "NG"; \
		fi
		@echo "Verification completed."

.PHONY: install uninstall compile check_shc
