# Repository development rules

Read README.md, docs/DEVELOPMENT.md, docs/CI.md and the relevant open issue before editing.

- Keep emulator implementation in its own repository. Do not rebuild it from game CI.
- Use jrasm as an external tool. Do not vendor it or claim a redistribution license without verification.
- Register every build/test input and transitive dependency. Distinguish embedded assets from gallery images.
- Separate build fingerprints from test fingerprints. Skipping requires trusted successful evidence and valid artifacts, not just a path filter or cache hit.
- Do not skip work because the immediately previous commit touched no relevant files; it may have failed or been cancelled.
- Change selection must be tested for shared dependencies, deletion, renames, unknown paths, missing artifacts and cancelled predecessors before production use.
- Run make check. Initial CI validates repository structure and the selector only; it does not verify games.
- Keep tests and publishing separate. PR code must not receive publication credentials or write trusted success receipts.
- Publish only explicitly selected, verified game versions. Preserve existing unrelated Wiki pages.
- Do not change visibility, billing, access rules or deploy externally without explicit authorization.
- Never commit ROMs, manufacturer font data, private recordings, secrets or local paths. Use synthetic fixtures in public tests.
- Keep provenance, copyright and necessary license texts. Record only concise technical evidence; no conversation transcripts, personal context or duplicated planning reports.
- Keep task status in Issues. Close a task only after its acceptance criteria have actual evidence.
