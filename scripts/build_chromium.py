#!/usr/bin/env python3
"""Fetch and build the pinned full Chromium browser, independently of CEF.

Generated dependencies and build output stay in AELO_CHROMIUM_ROOT or .build/.
This never installs an app, launches a browser or migrates a user profile.
"""
import argparse
import ast
import fcntl
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

PROJECT = Path(__file__).resolve().parents[1]
LOCK = json.loads((PROJECT / "chromium.lock.json").read_text())
MIN_FREE_BYTES = 160 * 1024**3


class ChromiumBuild:
    def __init__(self, root=None, jobs=4):
        self.root = Path(root or os.environ.get(
            "AELO_CHROMIUM_ROOT", PROJECT / ".build/chromium")).expanduser().resolve()
        if self.root in (Path("/"), Path.home(), PROJECT):
            raise ValueError("Use a dedicated Chromium build directory")
        if " " in str(self.root):
            raise ValueError("Chromium's checkout path must not contain spaces")
        self.tools = self.root / "depot_tools"
        self.checkout = self.root / "checkout"
        self.src = self.checkout / "src"
        self.out = self.src / "out/Aelo"
        self.jobs = jobs
        metal = os.environ.get("AELO_METAL_TOOLCHAIN_DIR")
        self.metal_tools = Path(metal).expanduser().resolve() if metal else None
        if self.metal_tools and any(not (self.metal_tools / tool).is_file()
                                    or not os.access(self.metal_tools / tool, os.X_OK)
                                    for tool in ("metal", "metallib")):
            raise ValueError("AELO_METAL_TOOLCHAIN_DIR must contain executable metal and metallib tools")
        self.env = dict(os.environ)
        self.env.update({
            "PATH": str(self.root / "bin") + os.pathsep + str(self.tools) + os.pathsep + os.environ.get("PATH", ""),
            "DEPOT_TOOLS_UPDATE": "0",
            "DEPOT_TOOLS_METRICS": "0",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_COUNT": "3",
            "GIT_CONFIG_KEY_0": "protocol.version",
            "GIT_CONFIG_VALUE_0": "2",
            "GIT_CONFIG_KEY_1": "http.version",
            "GIT_CONFIG_VALUE_1": "HTTP/1.1",
            "GIT_CONFIG_KEY_2": "pack.threads",
            "GIT_CONFIG_VALUE_2": "2",
            "CIPD_CACHE_DIR": str(self.root / "cipd-cache"),
            "VPYTHON_VIRTUALENV_ROOT": str(self.root / "vpython"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "GOCACHE": str(self.root / "go-cache"),
            "GOMODCACHE": str(self.root / "go-modules"),
            # Public DEPS objects need no account. Skip interactive LUCI auth
            # and keep gsutil's config/state inside this dedicated build root.
            "SWARMING_HEADLESS": "1",
            "BOTO_CONFIG": str(self.root / "public-downloads.boto"),
            "BOTO_PATH": str(self.root / "public-downloads.boto"),
        })

    def run(self, *args, cwd=None, capture=False):
        print("+", " ".join(map(str, args)), flush=True)
        command = list(map(str, args))
        process = subprocess.Popen(command, cwd=cwd or self.root, env=self.env,
                                   text=True, stdout=subprocess.PIPE if capture else None)
        state = {"status": "running", "driver_pid": os.getpid(), "pid": process.pid,
                 "started_at": time.time(), "command": command}
        self.write_state(state)
        try:
            output, _ = process.communicate()
        except BaseException:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            self.write_state({**state, "status": "interrupted", "ended_at": time.time()})
            raise
        self.write_state({**state, "status": "completed" if process.returncode == 0 else "failed",
                          "returncode": process.returncode, "ended_at": time.time()})
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, command, output)
        return output

    def write_state(self, state):
        self.root.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=self.root, prefix=".state-", delete=False) as file:
            json.dump(state, file, indent=2)
            file.write("\n")
            name = file.name
        os.replace(name, self.root / "state.json")

    def check_previous_process(self):
        path = self.root / "state.json"
        if not path.exists():
            return
        state = json.loads(path.read_text())
        if state.get("status") != "running":
            return
        try:
            os.kill(state["pid"], 0)
        except ProcessLookupError:
            return
        except PermissionError:
            raise RuntimeError("Previous command's process cannot be inspected; do not start a duplicate")
        raise RuntimeError(f"Previous build command is still running (PID {state['pid']})")

    def preflight(self, require_xcode=True):
        if sys.platform != "darwin" or platform.machine() != "arm64":
            raise RuntimeError("This build currently targets Apple Silicon macOS")
        self.root.mkdir(parents=True, exist_ok=True)
        config = self.root / "public-downloads.boto"
        config_text = "[GSUtil]\nstate_dir = " + str(self.root / "gsutil-state") + "\nparallel_process_count = 1\n"
        if config.exists() and config.read_text() != config_text:
            raise RuntimeError("Build's public-downloads.boto differs; refusing to overwrite it")
        config.write_text(config_text)
        if not shutil.which("git-lfs", path=self.env["PATH"]):
            candidate = Path(os.environ.get("AELO_GIT_LFS", "/Applications/GitHub Desktop.app/Contents/Resources/app/git/libexec/git-core/git-lfs"))
            if not candidate.is_file() or not os.access(candidate, os.X_OK):
                raise RuntimeError("Git LFS is required by LiteRT. Install git-lfs or set AELO_GIT_LFS to its executable")
            local = self.root / "bin/git-lfs"
            local.parent.mkdir(exist_ok=True)
            if local.exists() or local.is_symlink():
                raise RuntimeError("Existing build-local git-lfs is unusable; inspect it before replacement")
            local.symlink_to(candidate.resolve())
        self.run("git-lfs", "version")
        free = shutil.disk_usage(self.root).free
        print(f"Free space: {free // 1024**3} GiB; source: {LOCK['revision']}", flush=True)
        if not self.src.exists() and free < MIN_FREE_BYTES:
            raise RuntimeError("Reserve at least 160 GiB before the initial Chromium checkout")
        if require_xcode:
            # DEVELOPER_DIR can select Xcode without changing xcode-select globally.
            self.run("xcodebuild", "-version")
            self.run("xcodebuild", "-checkFirstLaunchStatus")
            self.run("xcrun", "--sdk", "macosx", "--show-sdk-path")
            # Xcode 26 installs the Metal compiler as an optional component.
            # Execute it: --find can resolve a stub even when it is missing.
            if self.metal_tools:
                self.prepare_metal_tools()
                self.run(self.metal_tools / "metal", "--version")
            else:
                self.run("xcrun", "--sdk", "macosx", "metal", "--version")

    def gn_arguments(self):
        text = (PROJECT / "chromium/args.gn").read_text()
        if self.metal_tools:
            text += "\nangle_metal_toolchain_dir = " + json.dumps(str(self.root / "metal-tools")) + "\n"
        return text

    def prepare_metal_tools(self):
        # Metal ignores CLANG_MODULE_CACHE_PATH. Its explicit compiler flag
        # keeps module output within the dedicated, writable build directory.
        directory = self.root / "metal-tools"
        directory.mkdir(exist_ok=True)
        cache = self.root / "metal-module-cache"
        cache.mkdir(exist_ok=True)
        for tool in ("metal", "metallib"):
            args = [str(self.metal_tools / tool)]
            if tool == "metal":
                args.append("-fmodules-cache-path=" + str(cache))
            script = '#!/bin/sh\n# Generated by Aelo Chromium build.\nexec ' + shlex.join(args) + ' "$@"\n'
            path = directory / tool
            if path.exists() and path.read_text() != script:
                raise RuntimeError(f"Existing Metal adapter differs; inspect before replacement: {path}")
            path.write_text(script)
            path.chmod(0o755)

    def ensure_git(self, path, repository, revision):
        if not (path / ".git").exists():
            path.mkdir(parents=True, exist_ok=True)
            if any(path.iterdir()):
                raise RuntimeError(f"Refusing to initialize a nonempty source directory: {path}")
            self.run("git", "init", path)
            self.run("git", "remote", "add", "origin", repository, cwd=path)
        remote = self.run("git", "remote", "get-url", "origin", cwd=path, capture=True).strip()
        if remote != repository:
            raise RuntimeError(f"Unexpected source origin at {path}; refusing to change it")
        head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=path,
                              env=self.env, text=True, capture_output=True)
        if head.returncode:
            self.run("git", "fetch", "--no-tags", "--depth=1", "--progress", "origin", revision, cwd=path)
            self.run("git", "checkout", "--detach", revision, cwd=path)
        elif head.stdout.strip() != revision:
            raise RuntimeError(f"Source revision differs from lock at {path}; refusing to reset it")

    def fetch(self):
        self.preflight(require_xcode=False)
        self.ensure_git(self.tools, LOCK['depot_tools_repository'], LOCK['depot_tools_revision'])
        self.checkout.mkdir(exist_ok=True)
        config = self.checkout / ".gclient"
        spec = "solutions = " + repr([{
            "name": "src", "url": LOCK['repository'], "managed": False,
            "custom_deps": LOCK.get("custom_deps", {}), "custom_vars": {"checkout_pgo_profiles": False},
        }]) + "\ntarget_os = ['mac']\n"
        if config.exists() and config.read_text() != spec:
            raise RuntimeError("Existing .gclient configuration differs; inspect it before continuing")
        if self.src.exists() and (self.src / ".git").exists():
            self.check_source_changes()
        config.write_text(spec)
        self.ensure_git(self.src, LOCK['repository'], LOCK['revision'])
        self.run(self.tools / "gclient", "sync", "--nohooks", "--no-history",
                 f"--revision=src@{LOCK['revision']}", f"--jobs={self.jobs}", cwd=self.checkout)
        self.verify_revision()
        self.validate_dependencies()

    def validate_dependencies(self):
        manifest = self.checkout / ".gclient_entries"
        if not manifest.is_file():
            raise RuntimeError("Dependency manifest is missing; complete fetch before building")
        document = ast.parse(manifest.read_text())
        assignments = [node for node in document.body if isinstance(node, ast.Assign)
                       and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
                       and node.targets[0].id == "entries"]
        if len(assignments) != 1:
            raise RuntimeError("Unexpected dependency manifest format")
        entries = ast.literal_eval(assignments[0].value)
        if not isinstance(entries, dict):
            raise RuntimeError("Dependency manifest entries must be a dictionary")
        checked = 0
        for relative, url in entries.items():
            if not isinstance(url, str) or "@" not in url:
                continue
            expected = url.rsplit("@", 1)[-1]
            if not re.fullmatch(r"[0-9a-f]{40}", expected):
                continue
            path = (self.checkout / relative).resolve()
            if path != self.src and self.src not in path.parents:
                raise RuntimeError(f"Dependency path escapes source checkout: {relative}")
            if not (path / ".git").exists():
                raise RuntimeError(f"Missing Git dependency checkout: {relative}")
            result = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=path,
                                    env=self.env, text=True, capture_output=True, timeout=30)
            if result.returncode:
                raise RuntimeError(f"Incomplete Git dependency checkout: {relative} has no HEAD")
            if result.stdout.strip() != expected:
                raise RuntimeError(f"Unexpected dependency revision: {relative}")
            # Inspect index paths without content filters or recursive Gitlink
            # diffs; LFS filters can block an otherwise read-only diff scan.
            deleted = subprocess.run(["git", "ls-files", "--deleted", "-z"],
                                     cwd=path, env=self.env, text=True, capture_output=True,
                                     check=True, timeout=30)
            if deleted.stdout.strip():
                raise RuntimeError(f"Missing tracked files in dependency checkout: {relative}")
            checked += 1
        print(f"Validated {checked} pinned Git dependency checkouts", flush=True)

    def check_source_changes(self):
        dirty = self.run("git", "status", "--porcelain=v1", "-z", "--untracked-files=no",
                         cwd=self.src, capture=True)
        overrides = {path.removeprefix("src/"): url.rsplit("@", 1)[-1]
                     for path, url in LOCK.get("custom_deps", {}).items() if isinstance(url, str)}
        for entry in dirty.split("\0"):
            if not entry:
                continue
            path = entry[3:]
            expected = overrides.get(path)
            # A declared override changes a tracked gitlink's worktree HEAD.
            # Never excuse staged edits, ordinary source files or dirty deps.
            if entry[:2] == " M" and expected:
                tree = self.run("git", "ls-tree", "HEAD", "--", path,
                                cwd=self.src, capture=True)
                if tree.startswith("160000 commit "):
                    head = self.run("git", "rev-parse", "HEAD", cwd=self.src / path, capture=True).strip()
                    local = self.run("git", "status", "--porcelain", "--untracked-files=all",
                                     cwd=self.src / path, capture=True)
                    if head == expected and not local:
                        continue
            raise RuntimeError(f"Chromium has unexpected local source changes at {path}; do not sync over them")

    def verify_revision(self):
        actual = self.run("git", "rev-parse", "HEAD", cwd=self.src, capture=True).strip()
        if actual != LOCK['revision']:
            raise RuntimeError("Chromium source differs from chromium.lock.json")

    def patch(self):
        self.verify_revision()
        for patch in sorted((PROJECT / "chromium/patches").glob("*.patch")):
            reverse = subprocess.run(["git", "apply", "--reverse", "--check", str(patch)],
                                     cwd=self.src, env=self.env, capture_output=True)
            if reverse.returncode == 0:
                continue
            self.run("git", "apply", "--check", patch, cwd=self.src)
            self.run("git", "apply", patch, cwd=self.src)

    def sync_workspace_model(self):
        # One canonical engine-independent model, also compiled by standalone
        # regression tests. This generated copy is confined to the checkout.
        for name in ("aelo_workspace_model.h", "aelo_workspace_model.cc"):
            source = PROJECT / "chromium/workspace" / name
            destination = self.src / "chrome/browser/ui/views/tabs/vertical" / name
            if not destination.exists() or destination.read_bytes() != source.read_bytes():
                shutil.copyfile(source, destination)

    def configure(self):
        self.preflight()
        self.verify_revision()
        self.validate_dependencies()
        # gclient's own VPython can run before the shell GN/autoninja launchers
        # have their hermetic Python metadata. Bootstrap the pinned tools;
        # unlike update_depot_tools, this does not change their Git revision.
        self.run(self.tools / "ensure_bootstrap")
        self.patch()
        self.sync_workspace_model()
        self.run(self.tools / "gclient", "runhooks", cwd=self.checkout)
        self.out.mkdir(parents=True, exist_ok=True)
        args_text = self.gn_arguments()
        destination = self.out / "args.gn"
        if destination.exists() and destination.read_text() != args_text:
            raise RuntimeError("Existing args.gn differs; preserve and review it before replacement")
        destination.write_text(args_text)
        self.run(self.tools / "gn", "gen", "out/Aelo", "--fail-on-unused-args", cwd=self.src)

    def build(self):
        self.configure()
        self.run(self.tools / "autoninja", "-C", "out/Aelo", f"-j{self.jobs}", LOCK['target'], cwd=self.src)
        app = self.out / LOCK['app']
        if not app.is_dir():
            raise RuntimeError(f"Build did not produce expected app: {app}")
        print(f"Built full Chromium: {app}\nUse a disposable --user-data-dir for qualification.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("preflight", "fetch", "configure", "build"))
    parser.add_argument("--root")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    try:
        builder = ChromiumBuild(args.root, args.jobs)
        builder.root.mkdir(parents=True, exist_ok=True)
        with (builder.root / "driver.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("An Aelo Chromium build driver is already running")
            builder.check_previous_process()
            getattr(builder, args.action)()
            builder.write_state({"status": "action_completed", "action": args.action,
                                 "ended_at": time.time()})
    except (RuntimeError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"Chromium {args.action} stopped: {error}\n")


if __name__ == "__main__":
    main()
