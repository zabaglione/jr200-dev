# SPDX-License-Identifier: BSD-3-Clause
PYTHON ?= python3
DEVKIT_ROOT ?= ../..
PROJECT_DIR ?= $(CURDIR)
GAME_TOOL := $(DEVKIT_ROOT)/tools/game_project.py
RUNNER_TOOL := $(DEVKIT_ROOT)/tools/emulator_runner.py

.PHONY: validate build run package clean

validate:
	$(PYTHON) "$(GAME_TOOL)" validate --project "$(PROJECT_DIR)"

build:
	$(PYTHON) "$(GAME_TOOL)" build --project "$(PROJECT_DIR)"

run:
	@test -n "$(RUNNER_BUNDLE)" || { echo "RUNNER_BUNDLE is required" >&2; exit 2; }
	$(PYTHON) "$(RUNNER_TOOL)" run --project "$(PROJECT_DIR)" --bundle "$(RUNNER_BUNDLE)"

package:
	$(PYTHON) "$(GAME_TOOL)" package --project "$(PROJECT_DIR)"

clean:
	$(PYTHON) "$(GAME_TOOL)" clean --project "$(PROJECT_DIR)"
