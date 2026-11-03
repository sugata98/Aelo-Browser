# Aelo Browser

The first native macOS implementation currently uses **Orbit** as its preview app name. Project repository: [sugata98/Aelo-Browser](https://github.com/sugata98/Aelo-Browser).

A working native macOS browser prototype, built from the Arc reconstruction audit. This is the first implementation milestone, not full Arc feature parity.

The app is installed at **`~/Applications/Orbit Preview.app`**. Launch it from Finder. Building creates an ad-hoc signed local preview archive at `dist/Orbit-preview.zip`.

**Prebuilt download:** [Developer Preview 1](https://github.com/sugata98/Aelo-Browser/releases/tag/v0.1.0-preview.1) for Apple Silicon macOS. The app still uses the working name Orbit. This prerelease is ad-hoc signed and not notarized; macOS may block opening it. See the release notes for requirements and limitations.

## What works in this milestone

- Native macOS sidebar and browser window, with an original bundled icon.
- Real Chromium 156.0.8078.80 page rendering through CEF 156.0.15.
- Personal and Focus Spaces sharing the Default Profile; Work using a separate persistent Profile.
- New Spaces with either shared or separate browsing data.
- Tabs, tab renaming, pins, drag reordering, and archive/restore.
- Command Bar for URL/search navigation, tab switching across Spaces and application actions.
- Two live, resizable split panes.
- Back, forward, reload, native page dialogs and a download save dialog.
- Workspace export; atomic local persistence with a last-valid backup and corruption recovery.
- Saved URLs, active Space/tab, pins, window position and split membership restored after restart.
- Graceful shutdown, including a cancelable unsaved-page confirmation before closing a tab.

The three top shortcuts are starter links, not yet an editable Favorites system. Reloaded tabs restore their URL; full back/forward session history and unsaved form contents are not restored. The archive currently restores the most recent tab, without a searchable archive UI. Split geometry resets to equal widths after a restart.

## Shortcuts

| Action | Shortcut |
|---|---|
| New tab | ⌘T |
| Open Command Bar | ⌘L |
| Archive tab | ⌘W |
| Restore most recently archived tab | ⇧⌘T |
| Pin/unpin active tab | ⌘D |
| Toggle Split View | ⌘\\ |
| Reload | ⌘R |

Right-click a tab for pinning, renaming, splitting and archiving. In the command bar, use ↑/↓ and Return; Escape dismisses it. Profile details are available at the bottom of the sidebar.

## Build

Requires an Apple Silicon Mac, macOS 13 or later, Python 3.10+ and Apple's Command Line Tools. The app has been run on the current machine; macOS 13 itself has not been tested.

```sh
python3 scripts/build.py
```

The script downloads the pinned official CEF distribution if needed and checks its SHA-256 against `cef.lock.json`. It installs local CMake/Ninja tools into `.build/` only when they are unavailable, compiles the native app and helper processes, runs workspace tests, creates the icon, signs and verifies the app, installs it in `~/Applications/Orbit Preview.app`, and writes `dist/Orbit-preview.zip`. Override the dependency/cache directory with `ORBIT_BUILD_ROOT` if needed. Generated files and personal browser data are excluded from Git.

App replacement is restricted to a destination with this project's bundle identifier. Quit Orbit before rebuilding. This is an ad-hoc signed local development app, not a notarized public release; a Developer ID release pipeline is still required for distribution.

The renderer sandbox is enabled. No `--no-sandbox`, certificate-error bypass or web-security disabling flag is used. The engine is loaded dynamically using CEF's supported macOS loader and separate sandboxed helper bundles.

The workspace is under a cloud-managed Documents folder on this machine. Finder adds metadata that breaks signing there, so the build signs in temporary storage and installs outside Documents. Use the installed app or the verified ZIP.

## Data

Normal browsing data lives in **`~/Library/Application Support/OrbitPreview/`**, independently of Arc:

```text
workspace.json           Spaces, tabs, archive, pins and split membership
workspace.json.backup    Previous valid workspace snapshot
Profile-default/        Chromium data shared by Personal and Focus
Profile-<UUID>/          Chromium data for a separate Profile
Default/                Engine's installation/default-profile support data
engine.log              Local engine diagnostics
```

Workspace export includes organization and URLs. It does not include passwords, cookies, full browsing history or extension state. Those remain engine profile data. A corrupt workspace falls back to the last valid backup and preserves the damaged file as `.recovery`; if neither file is valid, startup refuses to overwrite them.

Test runs can use `ORBIT_DATA_DIR=/absolute/disposable/path`. Remote debugging is off by default and only opt-in when both `ORBIT_DATA_DIR` and `ORBIT_TEST_DEBUG_PORT` are provided. Do not use a cloud-synced folder for Chromium test profile databases.

## Architecture

`src/Workspace.mm` owns the engine-independent organization model and persistence. `src/Browser.mm` owns the AppKit shell, action routing and CEF sessions. A Profile maps to a distinct `CefRequestContext`; several Spaces can refer to one context. Each logical tab owns a lazily created Chromium browser view. Split View displays two such views. `src/Helper.cc` initializes the macOS sandbox and runs the subprocess entry point.

The first build uses native **CEF Alloy-style views**, because this machine did not have the disk space or full toolchain for a Chromium source checkout. This does **not** establish Chrome Web Store compatibility. The long-term all-features architecture remains a maintained Chromium fork; the compatibility gate must decide whether a more capable CEF integration can meet requirements first.

## Remaining parity work

1. **Compatibility gate:** real password-manager/native-messaging extensions, Web Store installation and updates, OAuth popups, passkeys, DRM/codecs, video calls, permissions and PDF/printing. These are not yet qualified.
2. **Migration and organization:** supported Arc export import with fixture tests, editable Favorites, nested folders, cross-Space moves, pinned-URL reset, configurable Auto-Archive, searchable archive, per-Space themes and richer multiwindow behavior.
3. **Arc interactions:** Peek, Little Arc, Air Traffic Control, Boosts with a DOM selector picker, capture/Easels and media/PiP controls.
4. **Services:** independent sync/sharing, encryption and recovery, optional AI features.
5. **Release readiness:** automated browser integration coverage, full accessibility audit, bounded renderer lifetime/tab suspension, multiple-display/window constraints, signed updates and notarization.

Browser-platform behavior that has not been tested should not be assumed to work just because Chromium is embedded. This preview is a foundation for development, rather than a replacement for a fully qualified daily browser.

## Validation

See [VALIDATION.md](VALIDATION.md) for current results and limitations. The [architecture audit and feature roadmap](docs/arc-rebuild-analysis.md), [REA evidence](docs/evidence/README.md), and [preview screenshots](docs/images/) are maintained in this repository. Local-only fixture server:

```sh
python3 tests/fixture_server.py
```

In Personal, navigate to `http://127.0.0.1:8765/set`; then open `/` in Focus and Work. Focus should show the cookie, while Work should show an empty cookie jar. The input field allows testing the unsaved-page confirmation using ⌘W. Tests use only synthetic data.

CEF is redistributed under its bundled license. Its license text is in the app resources, and Chromium credits are reachable from About Orbit → Licenses. This project uses no Arc binaries, branding assets or bundled fonts.
