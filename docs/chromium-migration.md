# Full Chromium migration

Branch: `feat/full-chromium-migration`. The published
`v0.1.0-preview.1` remains the native AppKit/CEF preview.

## Status

The full Chromium source checkout is present at the pinned revision below.
Xcode 26.6 and its macOS 26.5 SDK pass preflight. Dependency sync completed
successfully on 3 November 2026 at 11:16 IST. The reviewed isolation patch has
been applied, and Chromium's dependency hooks completed successfully. The
initial GN launcher stopped on missing depot_tools hermetic-Python metadata;
the build now explicitly runs the pinned tools' `ensure_bootstrap` before
configuration. That bootstrap does not update the depot_tools Git revision.
GN generation subsequently succeeded, creating 36,370 targets. The first build
scheduler stopped on a missing LiteRT schema: its earlier failed LFS checkout
had left an uninitialized working tree despite gclient's successful return.
The incomplete files were preserved under `.build/chromium/recovery/` and
LiteRT was restored at its original pinned commit, and `git lfs fsck --objects`
passed. Independent validation now checks all 150 pinned Git dependencies
before configuration and after sync. Full Chromium compilation has started:
the first progress check confirmed 255 completed native object files in Ninja's
output log. The first compile attempt finished 1,052 build steps before stopping
at ANGLE's Metal shaders because Xcode's optional Metal Toolchain was missing.
Preflight now executes the selected Metal compiler so this prerequisite fails early.
The optional Apple component is installed and both `metal` and `metallib`
version commands succeed. Compilation is being resumed with ANGLE's existing
`angle_metal_toolchain_dir` option because the default `xcrun` route still
selects Xcode's nonworking placeholder in the coding sandbox.
Build completion, launch and workspace integration have
**not** been verified. The target is upstream `chrome`, including browser
profile and extension services, separately from the CEF targets.

The user has prioritized completing and launching this build. CEF UI work is
paused. A branded upstream build alone will not establish that the existing
workspace shell has been ported or that every Chrome extension works.

## Source and build

`chromium.lock.json` pins Chromium **156.0.8078.80**, commit
`fb096c0011f9d50f0a264a9376420cdea9c421e3`, and depot_tools commit
`816da11f80777dcf8c10bdaa84df18450dcba12a`. The target is `chrome` and the
expected output is `Aelo.app`.

The Chromium commit was confirmed through Gitiles and the
[official GitHub mirror](https://github.com/chromium/chromium).
The original GoogleSource fetch stalled during object enumeration; the exact
same commit was fetched from that mirror. Git integrity checking remains enabled.

Two immutable dependency snapshots across three checkout paths are recorded in the lock and
`chromium/dependency-overrides.json`. The original formatter-helper and
search-engine-data commits returned HTTP 500 from Git and HTTP 404 from their
public Gitiles commit endpoints. The replacement snapshots are published by
the same upstream repositories: formatter `47dce846…` (23 September 2026) and
search definitions `effde84e…` (16 September 2026). The formatter is included,
not omitted. Search-data generation and runtime behavior still need validation.

The browser source remains at the stable release commit (also confirmed by
[Chromium Dash](https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Mac&num=1)).
With these explicit substitutions and the isolation patch, this is an Aelo
fork build, not a byte-for-byte reproduction of the original upstream DEPS.
Revisit both overrides when the original public revisions become available.

A separate transport-only override fetches LiteRT from the
[official upstream repository](https://github.com/google-ai-edge/LiteRT) at the
**same** `4dac1538b76bc20bb7f2ba314bcc89dc57c0ee2b` commit. The Chromium Git
mirror returned HTTP 405 for Git LFS; upstream serves the pinned objects.
Git LFS object verification stays enabled. This does not substitute a different
LiteRT source version or disable the WebNN build.

The formatter snapshot also covers Web Page Replay's nested copy at
`src/third_party/webpagereplay/third_party/clang-format/script`. The first sync
with top-level overrides reached this nested dependency and failed on the same
unavailable original commit. Both formatter locations now use the identical
verified public snapshot.

Follow the [upstream macOS build prerequisites](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md).
Use full Xcode with its license accepted by the operator and first-launch
components installed, including the optional Metal Toolchain needed by ANGLE.
Apple documents installation through Xcode Settings → Components or
`xcodebuild -downloadComponent MetalToolchain` in its
[additional components guide](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).
Command-line exports failed to fetch Apple's component catalog, including
after the reported Xcode cache/mapping-file permissions were granted. Xcode's
Components UI installed Metal Toolchain 26.6 (17F109). The installed compiler
reports Apple Metal 32023.883 and both compiler and library tools execute.
The sandbox's `xcrun` still selects a placeholder. Set
`AELO_METAL_TOOLCHAIN_DIR` to the installed Apple toolchain's `usr/bin`
directory to use ANGLE's upstream explicit toolchain option. Preflight verifies
the compiler, and generated GN arguments record that directory; no Chromium
source workaround or graphics feature disablement is needed. The mounted
component path can change after an OS restart, so inspect it before reuse.
The prior compiled outputs are retained for incremental compilation.
Existing GN argument changes must be reviewed and backed up before replacement;
the build driver continues to reject an unexpected existing `args.gn`.
The first explicit-toolchain shader action then reached Apple's compiler but
failed writing its module cache under the macOS per-user `C/clang/ModuleCache`
directory. A specific permission grant did not resolve the failure. A direct
retry with `-fmodules-cache-path` inside `.build/chromium/` compiled the same
shader successfully (150,688-byte AIR output). The driver now generates small
local adapters for ANGLE: `metal` receives that explicit cache flag and
`metallib` delegates unchanged. These execute the installed Apple tools and
keep compiler caches inside the build root. The resumed full build has now
produced both ANGLE outputs: a 150,608-byte AIR file and a 360,535-byte
Metal library. The driver lock is held and the Ninja output log is advancing.
The Metal shader blocker is resolved; final browser build and launch remain
unverified.
Reserve at least 160 GiB for the initial checkout/build;
actual usage depends on build options.

Git LFS is required by LiteRT's pinned checkout. Preflight uses an existing
`git-lfs` on PATH, or a build-local symlink to GitHub Desktop's bundled copy
(3.7.1 on this machine). `AELO_GIT_LFS` can specify another installed executable.
This does not change global Git configuration or install software system-wide.

```sh
python3 scripts/build_chromium.py preflight
python3 scripts/build_chromium.py fetch --jobs 4
python3 scripts/build_chromium.py build --jobs 4
```

`build` runs hooks, applies the patch series, generates `out/Aelo` from
`chromium/args.gn`, and compiles `chrome`. `configure` stops before compilation.
Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` to select Xcode
for a command; the script does not change the global developer selection.

The default build root is `.build/chromium/`. `AELO_CHROMIUM_ROOT` or `--root`
can select another dedicated path without spaces. Unexpected origins,
revisions, source changes or existing configuration block replacement.
A driver lock prevents duplicate invocations. `state.json` records command
PID, time and outcome; a still-running interrupted command blocks a new driver.
The source guard accepts a changed tracked gitlink only when its HEAD matches
a declared dependency override and its own worktree is clean. Unexpected
source edits, staged changes and dirty overridden dependencies still block sync.
The dependency validator independently reads the generated dependency manifest,
checks pinned Git HEADs and detects missing indexed files. It uses index-path
checks without invoking LFS content filters, and bounds each Git query with a
timeout. This catches incomplete checkouts that the sync return code missed.

Public Google Storage dependencies use an anonymous headless downloader.
Its config, state, Python environments and caches stay inside the build root.
This avoids the interactive LUCI authentication path that returned
`Operation not permitted` in the coding sandbox. The initially failing Perfetto
object downloaded successfully and matched its pinned SHA-256 before sync was
resumed. DEPS integrity checks and TLS verification remain enabled.

Generated source, dependencies, profiles, logs and bundles are excluded from
Git. This script does not install or replace the released preview. Expected
output after a successful build:

```text
.build/chromium/checkout/src/out/Aelo/Aelo.app
```

## Isolation and data preservation

The four-file patch assigns these independent macOS identities:

| Surface | Full Chromium build |
|---|---|
| Product | Aelo |
| Bundle identifier | `dev.aelo.chromium` |
| Default user data | `~/Library/Application Support/Aelo/Chromium/` |
| Keychain service/account | `Aelo Safe Storage` / `Aelo` |
| System native-messaging manifests | `/Library/Application Support/Aelo/Chromium/NativeMessagingHosts` |
| User native-messaging manifests | `NativeMessagingHosts` within the selected Chromium user-data directory |

Branding alone leaves upstream's hardcoded Keychain and system host identities
shared with Chromium. The patch separates them along with the default data
root. This configuration is source-reviewed; live isolation is still unverified.

Existing CEF directories, workspace files, Arc data and other browsers' data
are preserved. Do not point full Chromium at a CEF profile or copy encrypted
databases into its new root. Migration needs a versioned, reversible design
and fixtures. Spaces sharing a Profile must retain that mapping; separate
Profiles must retain isolated browser data.

Launch qualification must use disposable `--user-data-dir` storage outside
cloud folders. Preserve renderer sandboxing, certificate checks and web
security. Native-messaging tests must use disposable manifests, not another
browser's namespace.

## Validation and remaining work

Established on 3 November 2026:

- Chromium source revision matches the lock.
- Full dependency sync completed with the documented public snapshot overrides.
- Xcode version, first-launch status and SDK preflight pass.
- `git apply --check` accepts the isolation patch against the pinned source.
- Offline tests cover source-directory/origin preservation, pinned build
  identity, duplicate-process protection and ICNS container assembly.
- The legacy CEF build and native workspace tests pass. Its generated ICNS
  decodes with `sips`; packaging verifies recursive app signatures.

Required before declaring the engine switch complete:

1. Complete dependency sync and hooks; compile and launch the full browser.
2. Verify sandboxed renderer operation and profile/Keychain isolation using
   disposable data. Record the actual binary and toolchain result.
3. Integrate the independent workspace with Chromium browser services, including
   shared/separate Profiles and two live panes. Preserve old data throughout.
4. Reproduce the documented CEF shutdown watchdog and establish a causal fix.
   A traced ordinary shutdown completed in 0.212 seconds. The deterministic
   quit-during-creation case also completed teardown. Neither reproduced the
   watchdog, so the reported issue remains unresolved.
5. Qualify MV3 service workers, installation/updates, permissions, popups and
   native messaging with synthetic fixtures. Real password-manager/Web Store
   compatibility is still unqualified.
6. Verify a supported Arc export schema from a sanitized fixture before
   implementing its parser. Do not guess private profile schemas.

The paused CEF investigation reproduced a blank pane after layout changes;
an experimental host-lifetime change is unqualified and must not be described
as a verified shutdown fix.
