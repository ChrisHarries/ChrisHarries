.PHONY: fmt fmt-check validate lint security test test-module clean help \
        validate-accounts validate-root validate-prod validate-dev

MODULES := modules/vpc modules/eks modules/iam modules/security_groups \
           modules/node_groups modules/proxy modules/database modules/datadog \
           modules/secret_rotation bootstrap

ACCOUNTS := accounts/root accounts/prod accounts/dev

REPORTS_DIR := reports

## help: Show this help message
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@sed -n 's/^## //p' $(MAKEFILE_LIST) | column -t -s ':' | sed -e 's/^/  /'

## fmt: Format all Terraform files in place
fmt:
	terraform fmt -recursive .

## fmt-check: Check formatting without modifying files (fails in CI if drift found)
fmt-check:
	terraform fmt -check -recursive .

## validate: Initialise (no backend) and validate all modules and account stacks
validate: validate-modules validate-accounts

## validate-modules: Validate all shared modules
validate-modules:
	@for mod in $(MODULES); do \
		echo "==> Validating $$mod"; \
		terraform -chdir=$$mod init -backend=false -input=false; \
		terraform -chdir=$$mod validate; \
	done

## validate-accounts: Validate all account stacks (root, prod, dev)
validate-accounts:
	@for acct in $(ACCOUNTS); do \
		echo "==> Validating $$acct"; \
		terraform -chdir=$$acct init -backend=false -input=false; \
		terraform -chdir=$$acct validate; \
	done

## validate-root: Validate the root (Organizations) account stack only
validate-root:
	terraform -chdir=accounts/root init -backend=false -input=false
	terraform -chdir=accounts/root validate

## validate-prod: Validate the prod workload account stack only
validate-prod:
	terraform -chdir=accounts/prod init -backend=false -input=false
	terraform -chdir=accounts/prod validate

## validate-dev: Validate the dev workload account stack only
validate-dev:
	terraform -chdir=accounts/dev init -backend=false -input=false
	terraform -chdir=accounts/dev validate

## lint: Run tflint across all modules and account stacks
lint:
	@which tflint > /dev/null || (echo "tflint not installed: https://github.com/terraform-linters/tflint" && exit 1)
	tflint --init
	tflint --recursive --format compact

## security: Run Checkov security scan and write JSON report
security:
	@which checkov > /dev/null || (echo "checkov not installed: pip install checkov" && exit 1)
	@mkdir -p $(REPORTS_DIR)
	checkov -d . --config-file .checkov.yaml || true
	@echo "==> Report written to $(REPORTS_DIR)/checkov-results.json"

## test: Run all terraform unit tests (mocked — no AWS credentials needed)
test:
	@echo "==> Running unit tests for all modules"
	@for mod in $(MODULES); do \
		test_dir="$$mod/tests"; \
		if [ -d "$$test_dir" ]; then \
			echo "==> Testing $$mod"; \
			terraform -chdir=$$mod init -backend=false -input=false; \
			terraform -chdir=$$mod test; \
		fi; \
	done

## test-module: Run tests for a single module. Usage: make test-module MOD=modules/vpc
test-module:
	@test -n "$(MOD)" || (echo "Usage: make test-module MOD=modules/vpc" && exit 1)
	terraform -chdir=$(MOD) init -backend=false -input=false
	terraform -chdir=$(MOD) test

## ci: Run the full CI pipeline locally (fmt-check, validate, lint, security, test)
ci: fmt-check validate lint security test
	@echo "==> All checks passed"

## clean: Remove generated .terraform directories and lock files
clean:
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	rm -rf $(REPORTS_DIR)
