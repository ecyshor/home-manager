.PHONY: update help

# Default target when running just 'make'
.DEFAULT_GOAL := help

# Update nix flake and its inputs
update:
	@echo "Updating nix flake and its inputs..."
	nix flake update

# Help command to show available targets
help:
	@echo "Available targets:"
	@echo "  update  - Update nix flake and its inputs"
	@echo "  help    - Show this help message"

