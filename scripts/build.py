#!/usr/bin/env python3
"""Reproducible Apple Silicon developer build; dependencies remain in .build/."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request

PROJECT = Path(__file__).resolve().parents[1]
WORK = Path(os.environ.get("AELO_BUILD_ROOT", str(PROJECT / ".build"))).expanduser().resolve()
APP = Path.home() / "Applications/Aelo.app"
BUILD = WORK / "aelo-build"

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def tool(name):
    system = shutil.which(name)
    if system:
        return system
    local = WORK / "build-tools"
    binary = local / ("cmake/data/bin/" + name if name in ("cmake", "ctest") else "bin/" + name)
    if not binary.exists():
        run(sys.executable, "-m", "pip", "install", "--target", local, "cmake==4.4.4", "ninja==1.13.2")
    return str(binary)

def engine():
    if os.environ.get("AELO_CEF_ROOT"):
        return Path(os.environ["AELO_CEF_ROOT"]).resolve()
    lock = json.loads((PROJECT / "cef.lock.json").read_text())
    root = WORK / "cef-sdk" / lock["name"].removesuffix(".tar.bz2")
    if root.exists():
        return root
    archive = WORK / "cef.tar.bz2"
    if not archive.exists():
        print("Downloading pinned Chromium Embedded Framework…", flush=True)
        urllib.request.urlretrieve("https://cef-builds.spotifycdn.com/" + urllib.parse.quote(lock["name"]), archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != lock["sha256"]:
        raise RuntimeError("CEF archive does not match cef.lock.json; refusing to extract")
    destination = root.parent.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        for item in tar.getmembers():
            target = (destination / item.name).resolve()
            if destination not in target.parents:
                raise RuntimeError("Archive path escapes destination")
            if item.issym() and destination not in (target.parent / item.linkname).resolve().parents:
                raise RuntimeError("Archive symlink escapes destination")
        tar.extractall(destination)
    return root

def write_plist(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(data, stream)

def package(cef):
    global APP
    destination = APP
    staging = Path(tempfile.mkdtemp(prefix="aelo-package-"))
    APP = staging / "Aelo.app"
    content = APP / "Contents"
    for folder in ("MacOS", "Resources", "Frameworks"):
        (content / folder).mkdir(parents=True, exist_ok=True)
    shutil.copy2(BUILD / "aelo", content / "MacOS/Aelo")
    framework = content / "Frameworks/Chromium Embedded Framework.framework"
    if not framework.exists():
        run("ditto", cef / "Release/Chromium Embedded Framework.framework", framework)
    for suffix, identifier in (("", ""), (" (Alerts)", ".alerts"), (" (GPU)", ".gpu"), (" (Plugin)", ".plugin"), (" (Renderer)", ".renderer")):
        name = "Aelo Helper" + suffix
        helper = content / "Frameworks" / (name + ".app") / "Contents"
        (helper / "MacOS").mkdir(parents=True, exist_ok=True)
        shutil.copy2(BUILD / "aelo_helper", helper / "MacOS" / name)
        write_plist(helper / "Info.plist", {
            "CFBundleExecutable": name, "CFBundleIdentifier": "dev.aelo.preview.helper" + identifier,
            "CFBundleName": name, "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
            "LSBackgroundOnly": True, "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": True,
        })
    write_plist(content / "Info.plist", {
        "CFBundleExecutable": "Aelo", "CFBundleIdentifier": "dev.aelo.preview",
        "CFBundleName": "Aelo", "CFBundleDisplayName": "Aelo",
        "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
        "CFBundleIconFile": "Aelo", "NSHighResolutionCapable": True, "LSMinimumSystemVersion": "13.0",
        "NSPrincipalClass": "AeloApplication", "NSSupportsAutomaticGraphicsSwitching": True,
        "NSCameraUsageDescription": "Allow a website you choose to use your camera.",
        "NSMicrophoneUsageDescription": "Allow a website you choose to use your microphone.",
    })
    shutil.copy2(PROJECT / "resources/home.html", content / "Resources/home.html")
    shutil.copy2(cef / "LICENSE.txt", content / "Resources/CEF-LICENSE.txt")
    run("xcrun", "clang++", "-fobjc-arc", "-fno-modules", "-framework", "Cocoa", PROJECT / "scripts/DrawIcon.mm", "-o", WORK / "draw-aelo-icon")
    iconset = WORK / "Aelo.iconset"
    iconset.mkdir(exist_ok=True)
    run(WORK / "draw-aelo-icon", WORK / "aelo-icon.png")
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{size}x{size}" + ("@2x" if scale == 2 else "") + ".png"
            subprocess.run(["sips", "-z", str(size * scale), str(size * scale), str(WORK / "aelo-icon.png"), "--out", str(iconset / name)], check=True, stdout=subprocess.DEVNULL)
    run("iconutil", "-c", "icns", iconset, "-o", content / "Resources/Aelo.icns")
    # Finder/File Provider may decorate generated .app folders in Documents.
    # Remove only signing-incompatible metadata on this build's artifacts.
    for attribute in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
        subprocess.run(["xattr", "-dr", attribute, str(APP)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run("codesign", "--force", "--deep", "--sign", "-", APP)
    run("codesign", "--verify", "--deep", "--strict", APP)
    # Sign outside File Provider storage, then copy the finished app and archive.
    # Finder may attach folder metadata under Documents while codesign runs.
    if destination.exists():
        existing = plistlib.loads((destination / "Contents/Info.plist").read_bytes())
        if existing.get("CFBundleIdentifier") != "dev.aelo.preview":
            raise RuntimeError("Destination belongs to a different application; refusing to replace it")
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    run("ditto", "--norsrc", "--noextattr", APP, destination)
    archive = PROJECT / "dist/Aelo-preview.zip"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if archive.exists():
        archive.unlink()
    run("ditto", "-c", "-k", "--keepParent", "--norsrc", APP, archive)
    run("codesign", "--verify", "--deep", "--strict", destination)
    shutil.rmtree(staging)
    APP = destination
    print(f"Built {APP}", flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-only", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin" or os.uname().machine != "arm64":
        raise RuntimeError("This first build targets Apple Silicon macOS only")
    WORK.mkdir(exist_ok=True)
    cef = engine()
    if not args.package_only:
        sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
        cmake = tool("cmake")
        run(cmake, "-S", PROJECT, "-B", BUILD, "-G", "Ninja", "-DCMAKE_MAKE_PROGRAM=" + tool("ninja"), "-DCEF_ROOT=" + str(cef), "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_SYSROOT=" + sdk)
        run(cmake, "--build", BUILD, "--parallel", "4")
        run(tool("ctest"), "--test-dir", BUILD, "--output-on-failure")
    package(cef)

if __name__ == "__main__":
    main()
