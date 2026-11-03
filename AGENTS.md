# Aelo Browser working instructions

- Product goal: an independent Chromium browser with Arc-style feature parity. The app name is Aelo; do not imply complete parity.
- Read README.md, VALIDATION.md and docs/arc-rebuild-analysis.md before substantial changes.
- Keep workspace organization independent of the browser engine. Spaces may share a Profile; different Profiles must isolate browser data.
- Do not read, modify, import or commit personal Arc/browser profiles without explicit task authorization. Use synthetic fixtures and disposable data directories for tests.
- Preserve the Chromium renderer sandbox, certificate validation and web security. Do not make compatibility tests pass by disabling protections.
- Build: `python3 scripts/build.py` on Apple Silicon macOS. It installs only this preview app under ~/Applications and creates dist/Aelo-preview.zip. Quit the preview before replacing its bundle.
- Run native workspace tests for persistence/model changes. Verify relevant live browser behavior for engine/UI changes; model tests alone do not establish browser compatibility.
- Keep .build/, dist/, app bundles, credentials, browser profiles and runtime logs out of Git. Put source-backed research and screenshots in docs/.
- Update VALIDATION.md when a previously unverified capability has actually been tested. Keep implemented, tested and planned features distinct.
