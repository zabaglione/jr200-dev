PYTHON ?= python3
.PHONY: check test plan release-audit jrasm-doctor jrasm-check runner-doctor template-validate template-build template-run template-package new-project game-validate game-build game-run game-package game-clean game-play wiki-check wiki-preview wiki-sync-dry-run wiki-sync-apply
check:
	$(PYTHON) tools/check_repository.py
	$(PYTHON) -m unittest discover -s tests -v

test:
	$(PYTHON) -m unittest discover -s tests -v

plan:
	$(PYTHON) tools/ci_plan.py

release-audit:
	$(PYTHON) tools/release_audit.py --strict

jrasm-doctor:
	$(PYTHON) tools/jrasm_tool.py doctor

jrasm-check:
	$(PYTHON) tools/jrasm_tool.py verify-fixture

runner-doctor:
	@test -n "$(RUNNER_BUNDLE)" || { echo "RUNNER_BUNDLE is required" >&2; exit 2; }
	$(PYTHON) tools/emulator_runner.py doctor --bundle "$(RUNNER_BUNDLE)"

template-validate:
	$(PYTHON) tools/game_project.py validate --project templates/minimal

template-build:
	$(PYTHON) tools/game_project.py build --project templates/minimal

template-run:
	@test -n "$(RUNNER_BUNDLE)" || { echo "RUNNER_BUNDLE is required" >&2; exit 2; }
	$(PYTHON) tools/emulator_runner.py run --project templates/minimal --bundle "$(RUNNER_BUNDLE)"

template-package:
	$(PYTHON) tools/game_project.py package --project templates/minimal

new-project:
	@test -n "$(ID)" -a -n "$(TITLE)" || { echo "ID and TITLE are required" >&2; exit 2; }
	$(PYTHON) tools/game_project.py new --id "$(ID)" --title "$(TITLE)"

game-validate game-build game-package game-clean:
	@test -n "$(PROJECT)" || { echo "PROJECT is required" >&2; exit 2; }
	$(PYTHON) tools/game_project.py $(@:game-%=%) --project "$(PROJECT)"

game-run:
	@test -n "$(PROJECT)" -a -n "$(RUNNER_BUNDLE)" || { echo "PROJECT and RUNNER_BUNDLE are required" >&2; exit 2; }
	$(PYTHON) tools/emulator_runner.py run --project "$(PROJECT)" --bundle "$(RUNNER_BUNDLE)"

game-play:
	@test -n "$(PROJECT)" -a -n "$(WEB_SITE)" || { echo "PROJECT and WEB_SITE are required" >&2; exit 2; }
	$(PYTHON) tools/game_play.py --project "$(PROJECT)" --web "$(WEB_SITE)" $(if $(PORT),--port "$(PORT)",)

wiki-check:
	$(PYTHON) tools/wiki/generate.py --include-candidates check

wiki-preview:
	$(PYTHON) tools/wiki/generate.py --include-candidates render --output build/wiki-preview

wiki-sync-dry-run:
	@test -n "$(WIKI_DIR)" || { echo "WIKI_DIR is required" >&2; exit 2; }
	$(PYTHON) tools/wiki/generate.py sync --wiki "$(WIKI_DIR)"

wiki-sync-apply:
	@test -n "$(WIKI_DIR)" || { echo "WIKI_DIR is required" >&2; exit 2; }
	$(PYTHON) tools/wiki/generate.py sync --wiki "$(WIKI_DIR)" --apply
