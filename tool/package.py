"""CI metadata and release packaging; Python standard library, no app runtime code."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?"
MATRIX = [
    dict(platform="android", arch="all", os="ubuntu-22.04", channel="stable"),
    dict(platform="ios", arch="arm64", os="macos-latest", channel="stable"),
    dict(platform="macos", arch="universal", os="macos-latest", channel="stable"),
    dict(platform="windows", arch="x64", os="windows-2022", channel="stable"),
    dict(platform="linux", arch="x64", os="ubuntu-22.04", channel="stable"),
    dict(platform="linux", arch="arm64", os="ubuntu-24.04-arm", channel="master"),
    dict(platform="web", arch="x64", os="ubuntu-22.04", channel="stable"),
]


def metadata(root, env):
    match = re.search(rf"^version:\s*({VERSION})\+([1-9][0-9]*)\s*$",
                      (root / "pubspec.yaml").read_text(), re.M)
    if not match:
        raise ValueError("pubspec.yaml must contain version: x.y.z[-prerelease]+build")
    version, number = match.groups()
    flutter = json.loads((root / ".fvmrc").read_text())["flutter"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", flutter):
        raise ValueError(".fvmrc must pin an exact stable Flutter version")
    if env.get("GITHUB_REF_TYPE") == "tag":
        if env.get("GITHUB_REF_NAME") != f"v{version}":
            raise ValueError("The version tag must match pubspec.yaml, without the +build suffix")
        label = version
        release_tag, prerelease = f"v{version}", "false"
    else:
        label = release_tag = "pre-alpha"
        prerelease = "true"
    selected = env.get("BUILD_PLATFORM", "all")
    matrix = [item for item in MATRIX if selected in ("all", item["platform"])]
    if not matrix:
        raise ValueError(f"Unknown platform: {selected}")
    return {"flutter": flutter, "version": version, "build-number": number,
            "release-tag": release_tag, "prerelease": prerelease,
            "label": label, "matrix": json.dumps({"include": matrix}, separators=(",", ":"))}


def output(values, env):
    text = "".join(f"{key}={value}\n" for key, value in values.items())
    if env.get("GITHUB_OUTPUT"):
        with open(env["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write(text)
    else:
        print(text, end="")


def prepare_release(root, env):
    """Prepare notes and replace the rolling tag/assets after all builds pass."""
    values = metadata(root, env)
    repo, sha, run = (env[key] for key in ("GITHUB_REPOSITORY", "GITHUB_SHA", "GITHUB_RUN_ID"))
    if (not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo)
            or not re.fullmatch(r"[0-9a-f]{40}", sha) or not run.isdigit()):
        raise ValueError("Invalid release build identity")
    url = f"{env.get('GITHUB_SERVER_URL', 'https://github.com')}/{repo}"
    channel = "pre-alpha（滚动预发布，仅保留本次构建产物）" if values["prerelease"] == "true" else "正式版本"
    notes = (f"发布渠道：{channel}\n\n"
             f"应用版本：`{values['version']}+{values['build-number']}`；"
             f"平台：`{env.get('BUILD_PLATFORM', 'all')}`\n\n"
             f"源码：[{sha[:8]}]({url}/commit/{sha}) · [构建记录]({url}/actions/runs/{run})\n\n"
             + (root / ".github/release-notes.md").read_text(encoding="utf-8"))
    notes_path = root / ".tmp/release-notes.md"
    notes_path.parent.mkdir(parents=True, exist_ok=True)
    notes_path.write_text(notes, encoding="utf-8")
    if values["prerelease"] == "false":
        return

    release_ids = subprocess.check_output(
        ["gh", "api", f"repos/{repo}/releases", "--paginate", "--jq",
         '.[] | select(.tag_name == "pre-alpha") | .id'], text=True).split()
    asset_ids = []
    for release_id in release_ids:
        asset_ids.extend(subprocess.check_output(
            ["gh", "api", f"repos/{repo}/releases/{release_id}/assets", "--paginate",
             "--jq", ".[].id"], text=True).split())
    # The workflow serializes all non-tag runs, including runs on other branches.
    # Only this reserved rolling tag is moved; version tags are never changed.
    subprocess.run(["git", "-C", str(root), "push", "origin",
                    f"+{sha}:refs/tags/pre-alpha"], check=True)
    # Remove every previous asset, including obsolete names/platforms.
    # API/auth errors fail the run instead of masquerading as a first release.
    for asset_id in asset_ids:
        subprocess.run(["gh", "api", "--method", "DELETE",
                        f"repos/{repo}/releases/assets/{asset_id}"], check=True)


def prepare_signing(env):
    keys = ["ANDROID_KEYSTORE_BASE64", "ANDROID_KEY_ALIAS",
            "ANDROID_STORE_PASSWORD", "ANDROID_KEY_PASSWORD"]
    present = [bool(env.get(key)) for key in keys]
    if any(present) and not all(present):
        raise ValueError("Configure all four ANDROID signing secrets together")
    if not any(present):
        return "test-signed"
    data = base64.b64decode(env[keys[0]], validate=True)
    if not data:
        raise ValueError("Android keystore is empty")
    key_path = Path(env["RUNNER_TEMP"]) / "5a-ui-release.jks"
    key_path.write_bytes(data)
    key_path.chmod(0o600)
    with open(env["GITHUB_ENV"], "a", encoding="utf-8") as stream:
        stream.write(f"ANDROID_KEYSTORE_PATH={key_path}\n")
    return "signed"


def require(path):
    if not path.exists():
        raise FileNotFoundError(f"Missing build output: {path}")
    return path


def copy_bundle(source, destination):
    shutil.copytree(require(source), destination, symlinks=True)
    return destination


def zip_tree(source, target):
    # Used for Web/Windows/iOS; macOS framework symlinks are preserved by DMG.
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for item in sorted(source.rglob("*")):
            if item.is_file():
                archive.write(item, item.relative_to(source).as_posix())


def tar_tree(source, target):
    with tarfile.open(target, "w:gz") as archive:
        archive.add(source, arcname="5a-ui")


def checksums(directory, name="SHA256SUMS"):
    files = sorted(path for path in directory.iterdir()
                   if path.is_file() and not path.name.endswith("SHA256SUMS"))
    if not files:
        raise ValueError("No release files to checksum")
    lines = []
    for path in files:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        lines.append(f"{digest.hexdigest()}  {path.name}\n")
    (directory / name).write_text("".join(lines), encoding="utf-8")


def package(root, platform, arch, version, label, signing="test-signed"):
    if not re.fullmatch(VERSION, version) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9.-]*", label):
        raise ValueError("Invalid package version or file label")
    if not any(item["platform"] == platform and item["arch"] == arch for item in MATRIX):
        raise ValueError("Unsupported platform/architecture combination")
    dist = root / "dist"
    dist.mkdir(exist_ok=True)
    (root / ".tmp").mkdir(exist_ok=True)
    prefix = f"5a-ui-{label}-{platform}"
    with tempfile.TemporaryDirectory(prefix="package-", dir=root / ".tmp") as temp:
        stage = Path(temp)
        if platform == "android":
            if signing not in ("signed", "test-signed"):
                raise ValueError("Unknown Android signing mode")
            for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
                source = require(root / f"build/app/outputs/flutter-apk/app-{abi}-release.apk")
                shutil.copy2(source, dist / f"{prefix}-{abi}-{signing}.apk")
            source = require(root / "build/app/outputs/bundle/release/app-release.aab")
            shutil.copy2(source, dist / f"{prefix}-{signing}.aab")
        elif platform == "ios":
            payload = stage / "Payload"
            payload.mkdir()
            apps = list((root / "build/ios/iphoneos").glob("*.app"))
            if len(apps) != 1:
                raise ValueError("Expected exactly one release iOS .app")
            copy_bundle(apps[0], payload / apps[0].name)
            zip_tree(stage, dist / f"{prefix}-arm64-unsigned.ipa")
        elif platform == "macos":
            app = copy_bundle(root / "build/macos/Build/Products/Release/5a-ui.app", stage / "5a-ui.app")
            # Do not label a single-architecture output as Universal.
            for binary in [app / "Contents/MacOS/5a-ui",
                           app / "Contents/Frameworks/App.framework/App",
                           app / "Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS"]:
                architectures = subprocess.check_output(["lipo", "-archs", str(require(binary))], text=True).split()
                if not {"arm64", "x86_64"}.issubset(architectures):
                    raise ValueError(f"Universal macOS package requires both architectures: {binary.name}")
            (stage / "Applications").symlink_to("/Applications")
            shutil.copy2(root / "LICENSE", stage / "LICENSE")
            subprocess.run(["hdiutil", "create", "-volname", "5a-ui", "-srcfolder", str(stage),
                            "-ov", "-format", "UDZO", str(dist / f"{prefix}-universal.dmg")], check=True)
            require(dist / f"{prefix}-universal.dmg")
        elif platform == "windows":
            bundle = copy_bundle(root / "build/windows/x64/runner/Release", stage / "5a-ui")
            for file in ("5a-ui.exe", "flutter_windows.dll", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"):
                require(bundle / file)
            shutil.copy2(root / "LICENSE", bundle / "LICENSE")
            zip_tree(bundle, dist / f"{prefix}-x64-portable.zip")
            compiler = shutil.which("ISCC") or str(Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Inno Setup 6/ISCC.exe")
            subprocess.run([compiler, f"/DAppVersion={version}", f"/DSourceDir={bundle}",
                            f"/DAppIcon={root / 'windows/runner/resources/app_icon.ico'}",
                            f"/DOutputDir={dist}", f"/DOutputName={prefix}-x64-setup",
                            str(root / "windows/packaging/installer.iss")], check=True)
            require(dist / f"{prefix}-x64-setup.exe")
        elif platform == "linux":
            bundle = copy_bundle(root / f"build/linux/{arch}/release/bundle", stage / "5a-ui")
            require(bundle / "5a-ui")
            shutil.copy2(root / "LICENSE", bundle / "LICENSE")
            tar_tree(bundle, dist / f"{prefix}-{arch}.tar.gz")
            deb = stage / "deb"
            copy_bundle(bundle, deb / "opt/5a-ui")
            desktop = deb / "usr/share/applications/5a-ui.desktop"
            desktop.parent.mkdir(parents=True)
            desktop.write_text("[Desktop Entry]\nType=Application\nName=5a-ui\n"
                               "Comment=3x-ui deployment and server status\nExec=/opt/5a-ui/5a-ui\n"
                               "Icon=5a-ui\nTerminal=false\nCategories=Network;\n"
                               "StartupWMClass=app.fivea.five_a_ui\n", encoding="utf-8")
            icon = deb / "usr/share/icons/hicolor/256x256/apps/5a-ui.png"
            icon.parent.mkdir(parents=True)
            shutil.copy2(root / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png", icon)
            control = deb / "DEBIAN/control"
            control.parent.mkdir()
            deb_arch = "amd64" if arch == "x64" else "arm64"
            libc = "2.35" if arch == "x64" else "2.39"
            control.write_text(f"Package: 5a-ui\nVersion: {version.replace('-', '~', 1)}\n"
                               f"Architecture: {deb_arch}\nMaintainer: 5a-ui contributors\n"
                               "Section: net\nPriority: optional\n"
                               f"Depends: libc6 (>= {libc}), libgtk-3-0, libstdc++6, liblzma5\n"
                               "Recommends: xdg-desktop-portal-gtk\n"
                               "Homepage: https://github.com/freephilx/5a-ui\n"
                               "Description: Flutter client for 3x-ui deployment and status\n", encoding="utf-8")
            subprocess.run(["dpkg-deb", "--root-owner-group", "--build", str(deb),
                            str(dist / f"{prefix}-{arch}.deb")], check=True)
            require(dist / f"{prefix}-{arch}.deb")
        elif platform == "web":
            require(root / "build/web/index.html")
            zip_tree(root / "build/web", dist / f"{prefix}.zip")
            bundle = stage / "5a-ui"
            bundle.mkdir()
            copy_bundle(root / "build/web", bundle / "web")
            shutil.copy2(require(root / "build/server/5a-ui-server"), bundle / "5a-ui-server")
            (bundle / "5a-ui-server").chmod(0o755)
            shutil.copy2(root / "LICENSE", bundle / "LICENSE")
            start = bundle / "start.sh"
            start.write_text('#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\n'
                             'export WEB_ROOT="${WEB_ROOT:-$PWD/web}"\nexec ./5a-ui-server\n', encoding="utf-8")
            start.chmod(0o755)
            (bundle / "README.txt").write_text(
                "5a-ui Web + Dart backend (Linux x64, Ubuntu 22.04 or newer)\n"
                "Run ./start.sh and open http://127.0.0.1:5000.\n"
                "Overrides: PORT, LOCAL_HOST, PUBLIC_ORIGIN, TURNSTILE_SITE_KEY, TURNSTILE_SECRET_KEY.\n"
                "Use HTTPS and PUBLIC_ORIGIN when exposing the service through a reverse proxy.\n",
                encoding="utf-8")
            tar_tree(bundle, dist / f"{prefix}-linux-x64.tar.gz")
    checksums(dist, f"{prefix}-{arch}-SHA256SUMS")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("metadata", "prepare-release", "android-signing", "clean-signing", "checksums"):
        commands.add_parser(name)
    build = commands.add_parser("package")
    for name in ("platform", "arch", "version", "label"):
        build.add_argument(f"--{name}", required=True)
    args = parser.parse_args()
    if args.command == "metadata":
        output(metadata(ROOT, os.environ), os.environ)
    elif args.command == "prepare-release":
        prepare_release(ROOT, os.environ)
    elif args.command == "android-signing":
        output({"signing": prepare_signing(os.environ)}, os.environ)
    elif args.command == "clean-signing":
        (Path(os.environ["RUNNER_TEMP"]) / "5a-ui-release.jks").unlink(missing_ok=True)
    elif args.command == "checksums":
        checksums(ROOT / "dist")
    else:
        package(ROOT, args.platform, args.arch, args.version, args.label,
                os.environ.get("ANDROID_SIGNING") or "test-signed")


if __name__ == "__main__":
    main()
