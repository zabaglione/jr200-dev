PYTHON ?= python3
.PHONY: check test plan
check:
	$(PYTHON) tools/check_repository.py
	$(PYTHON) -m unittest discover -s tests -v

test:
	$(PYTHON) -m unittest discover -s tests -v

plan:
	$(PYTHON) tools/ci_plan.py
