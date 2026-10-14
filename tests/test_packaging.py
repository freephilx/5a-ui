import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tool.package import checksums, metadata, package, prepare_release, prepare_signing


class PackagingTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write("pubspec.yaml", "name: five_a_ui\nversion: 1.2.3+4\n")
        self.write(".fvmrc", '{"flutter":"3.47.6"}\n')
        self.write("LICENSE", "test license")
        self.write(".github/release-notes.md", "Package installation instructions.\n")
        self.release_env = {"GITHUB_REPOSITORY": "owner/repo", "GITHUB_SHA": "a" * 40,
                            "GITHUB_RUN_ID": "42", "GITHUB_REF_TYPE": "branch",
                            "GITHUB_REF_NAME": "main", "BUILD_PLATFORM": "web"}

    def write(self, path, content="fixture"):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return target

    def test_metadata_preserves_sdk_version_and_selects_both_linux_architectures(self):
        values = metadata(self.root, {"BUILD_PLATFORM": "linux", "GITHUB_SHA": "a" * 40,
                                      "GITHUB_RUN_NUMBER": "42"})
        self.assertEqual(values["flutter"], "3.47.6")
        self.assertEqual(values["version"], "1.2.3")
        self.assertEqual(values["build-number"], "4")
        self.assertEqual(values["label"], "pre-alpha")
        self.assertEqual(values["release-tag"], "pre-alpha")
        self.assertEqual(values["prerelease"], "true")
        self.assertEqual([row["arch"] for row in json.loads(values["matrix"])["include"]], ["x64", "arm64"])

    def test_version_tags_are_stable_for_push_and_manual_runs(self):
        for event in ("push", "workflow_dispatch"):
            for version in ("1.2.3", "1.2.3-rc.1"):
                with self.subTest(event=event, version=version):
                    self.write("pubspec.yaml", f"version: {version}+4\n")
                    values = metadata(self.root, {"GITHUB_EVENT_NAME": event,
                                                  "GITHUB_REF_TYPE": "tag",
                                                  "GITHUB_REF_NAME": f"v{version}"})
                    self.assertEqual(values["label"], version)
                    self.assertEqual(values["release-tag"], f"v{version}")
                    self.assertEqual(values["prerelease"], "false")
                    self.assertEqual({row["platform"] for row in json.loads(values["matrix"])["include"]},
                                     {"android", "ios", "macos", "windows", "linux", "web"})

    def test_tag_must_match_pubspec_and_rolling_tag_cannot_be_released_as_stable(self):
        with self.assertRaisesRegex(ValueError, "tag must match"):
            metadata(self.root, {"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v9.0.0"})
        with self.assertRaisesRegex(ValueError, "tag must match"):
            metadata(self.root, {"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "pre-alpha"})

    def test_non_tag_builds_share_one_release_and_stable_asset_names(self):
        first = metadata(self.root, self.release_env)
        second = metadata(self.root, dict(self.release_env, GITHUB_SHA="b" * 40,
                                          GITHUB_RUN_NUMBER="99", GITHUB_REF_NAME="feature/example"))
        self.assertEqual(first, second)
        self.write("pubspec.yaml", "version: 2.0.0+5\n")
        third = metadata(self.root, self.release_env)
        self.assertEqual(first["release-tag"], third["release-tag"])
        self.assertEqual(first["label"], third["label"])

    def test_first_pre_alpha_moves_only_reserved_tag_and_records_build_source(self):
        with patch("tool.package.subprocess.check_output", return_value=""), \
                patch("tool.package.subprocess.run") as mutate:
            prepare_release(self.root, self.release_env)
        mutate.assert_called_once_with(
            ["git", "-C", str(self.root), "push", "origin",
             f"+{'a' * 40}:refs/tags/pre-alpha"], check=True)
        notes = (self.root / ".tmp/release-notes.md").read_text()
        self.assertIn("pre-alpha", notes)
        self.assertIn("`web`", notes)
        self.assertIn(f"https://github.com/owner/repo/commit/{'a' * 40}", notes)
        self.assertIn("https://github.com/owner/repo/actions/runs/42", notes)
        self.assertIn("Package installation instructions.", notes)

    def test_pre_alpha_removes_all_old_assets_even_for_single_platform(self):
        with patch("tool.package.subprocess.check_output", side_effect=["7\n", "101\n102\n103\n"]) as query, \
                patch("tool.package.subprocess.run") as mutate:
            prepare_release(self.root, self.release_env)
        # Pagination covers releases and assets beyond the first API page.
        self.assertTrue(all("--paginate" in call.args[0] for call in query.call_args_list))
        self.assertIn('select(.tag_name == "pre-alpha")', query.call_args_list[0].args[0][-1])
        self.assertIn("repos/owner/repo/releases/7/assets", query.call_args_list[1].args[0])
        deleted = [call.args[0][-1] for call in mutate.call_args_list if "DELETE" in call.args[0]]
        self.assertEqual(deleted, [f"repos/owner/repo/releases/assets/{asset}" for asset in (101, 102, 103)])

    def test_stable_release_does_not_move_tags_or_remove_assets(self):
        env = dict(self.release_env, GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v1.2.3")
        with patch("tool.package.subprocess.check_output") as query, \
                patch("tool.package.subprocess.run") as mutate:
            prepare_release(self.root, env)
        query.assert_not_called()
        mutate.assert_not_called()
        self.assertIn("正式版本", (self.root / ".tmp/release-notes.md").read_text())

    def test_release_lookup_errors_do_not_mutate_remote_state(self):
        with patch("tool.package.subprocess.check_output", side_effect=subprocess.CalledProcessError(1, "gh")), \
                patch("tool.package.subprocess.run") as mutate:
            with self.assertRaises(subprocess.CalledProcessError):
                prepare_release(self.root, self.release_env)
        mutate.assert_not_called()

    def test_failed_tag_update_does_not_delete_previous_assets(self):
        with patch("tool.package.subprocess.check_output", side_effect=["7\n", "101\n"]), \
                patch("tool.package.subprocess.run", side_effect=subprocess.CalledProcessError(1, "git")) as mutate:
            with self.assertRaises(subprocess.CalledProcessError):
                prepare_release(self.root, self.release_env)
        self.assertEqual(mutate.call_count, 1)
        self.assertEqual(mutate.call_args.args[0][0], "git")

    def test_invalid_platform_or_version_is_rejected(self):
        with self.assertRaises(ValueError):
            metadata(self.root, {"BUILD_PLATFORM": "unknown"})
        self.write("pubspec.yaml", "version: invalid\n")
        with self.assertRaises(ValueError):
            metadata(self.root, {})
        with self.assertRaises(ValueError):
            package(self.root, "web", "x64", "1.2.3", "../escape")

    def test_android_signing_requires_all_secrets_and_keeps_key_outside_repo(self):
        self.assertEqual(prepare_signing({}), "test-signed")
        with self.assertRaisesRegex(ValueError, "all four"):
            prepare_signing({"ANDROID_KEY_ALIAS": "fixture"})
        env = {"ANDROID_KEY_ALIAS": "fixture", "ANDROID_STORE_PASSWORD": "test-only",
               "ANDROID_KEY_PASSWORD": "test-only", "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"fixture").decode(),
               "RUNNER_TEMP": str(self.root), "GITHUB_ENV": str(self.root / "github-env")}
        self.assertEqual(prepare_signing(env), "signed")
        self.assertEqual((self.root / "5a-ui-release.jks").read_bytes(), b"fixture")
        self.assertEqual((self.root / "5a-ui-release.jks").stat().st_mode & 0o777, 0o600)
        self.assertNotIn("test-only", (self.root / "github-env").read_text())

    def test_android_outputs_are_explicitly_test_signed(self):
        for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
            self.write(f"build/app/outputs/flutter-apk/app-{abi}-release.apk")
        self.write("build/app/outputs/bundle/release/app-release.aab")
        package(self.root, "android", "all", "1.2.3", "1.2.3")
        artifacts = [p for p in (self.root / "dist").iterdir() if p.suffix in (".apk", ".aab")]
        self.assertEqual(len(artifacts), 4)
        self.assertTrue(all("test-signed" in p.name for p in artifacts))

    def test_ios_archive_has_payload_and_retains_executable_mode(self):
        binary = self.write("build/ios/iphoneos/Runner.app/Runner")
        binary.chmod(0o755)
        self.write("build/ios/iphoneos/Runner.app/Info.plist")
        package(self.root, "ios", "arm64", "1.2.3", "1.2.3")
        with zipfile.ZipFile(self.root / "dist/5a-ui-1.2.3-ios-arm64-unsigned.ipa") as archive:
            self.assertIn("Payload/Runner.app/Info.plist", archive.namelist())
            self.assertTrue(archive.getinfo("Payload/Runner.app/Runner").external_attr >> 16 & 0o111)

    def test_linux_archive_retains_libraries_permissions_and_deb_layout(self):
        binary = self.write("build/linux/x64/release/bundle/5a-ui")
        binary.chmod(0o755)
        lib = self.write("build/linux/x64/release/bundle/lib/libapp.so")
        (lib.parent / "alias.so").symlink_to("libapp.so")
        self.write("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png")

        def check_deb(command, **kwargs):
            self.assertEqual(command[:3], ["dpkg-deb", "--root-owner-group", "--build"])
            folder = Path(command[3])
            self.assertTrue((folder / "opt/5a-ui/5a-ui").exists())
            self.assertIn("Architecture: amd64", (folder / "DEBIAN/control").read_text())
            self.assertIn("Exec=/opt/5a-ui/5a-ui", (folder / "usr/share/applications/5a-ui.desktop").read_text())
            Path(command[4]).write_bytes(b"fixture-deb")

        with patch("tool.package.subprocess.run", side_effect=check_deb):
            package(self.root, "linux", "x64", "1.2.3", "1.2.3")
        with tarfile.open(self.root / "dist/5a-ui-1.2.3-linux-x64.tar.gz") as archive:
            self.assertTrue(archive.getmember("5a-ui/5a-ui").mode & 0o111)
            self.assertEqual(archive.getmember("5a-ui/lib/alias.so").linkname, "libapp.so")

    def test_web_service_archive_contains_backend_and_static_assets_only(self):
        self.write("build/web/index.html", "<html>5a-ui</html>")
        self.write("build/web/assets/font.ttf")
        self.write("build/server/5a-ui-server")
        self.write(".env", "MUST_NOT_SHIP=secret")
        package(self.root, "web", "x64", "1.2.3", "1.2.3")
        with zipfile.ZipFile(self.root / "dist/5a-ui-1.2.3-web.zip") as archive:
            self.assertEqual(set(archive.namelist()), {"index.html", "assets/font.ttf"})
        with tarfile.open(self.root / "dist/5a-ui-1.2.3-web-linux-x64.tar.gz") as archive:
            self.assertIn("5a-ui/web/index.html", archive.getnames())
            self.assertTrue(archive.getmember("5a-ui/5a-ui-server").mode & 0o111)
            self.assertTrue(archive.getmember("5a-ui/start.sh").mode & 0o111)
            self.assertNotIn("5a-ui/.env", archive.getnames())

    def test_windows_packages_include_runtime_and_share_installer_identity(self):
        for file in ("5a-ui.exe", "flutter_windows.dll", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"):
            self.write(f"build/windows/x64/runner/Release/{file}")

        def create_installer(command, **kwargs):
            defines = dict(value[2:].split("=", 1) for value in command if value.startswith("/D"))
            self.assertEqual(defines["AppVersion"], "1.2.3")
            self.assertEqual(defines["OutputName"], "5a-ui-1.2.3-windows-x64-setup")
            self.assertTrue((Path(defines["SourceDir"]) / "vcruntime140.dll").exists())
            (Path(defines["OutputDir"]) / f"{defines['OutputName']}.exe").write_bytes(b"installer")

        with patch("tool.package.subprocess.run", side_effect=create_installer):
            package(self.root, "windows", "x64", "1.2.3", "1.2.3")
        with zipfile.ZipFile(self.root / "dist/5a-ui-1.2.3-windows-x64-portable.zip") as archive:
            self.assertIn("vcruntime140_1.dll", archive.namelist())
            self.assertIn("LICENSE", archive.namelist())

    def test_macos_rejects_single_architecture_output(self):
        self.write("build/macos/Build/Products/Release/5a-ui.app/Contents/MacOS/5a-ui")
        with patch("tool.package.subprocess.check_output", return_value="arm64\n"):
            with self.assertRaisesRegex(ValueError, "both architectures"):
                package(self.root, "macos", "universal", "1.2.3", "1.2.3")

    def test_missing_output_and_empty_checksums_fail(self):
        with self.assertRaises(FileNotFoundError):
            package(self.root, "web", "x64", "1.2.3", "1.2.3")
        with self.assertRaises(ValueError):
            checksums(self.root / "dist")

    def test_combined_checksums_exclude_existing_manifests(self):
        self.write("dist/app.zip", "contents")
        self.write("dist/android-SHA256SUMS", "old manifest")
        checksums(self.root / "dist")
        expected = f"{hashlib.sha256(b'contents').hexdigest()}  app.zip\n"
        self.assertEqual((self.root / "dist/SHA256SUMS").read_text(), expected)
        checksums(self.root / "dist")
        self.assertEqual((self.root / "dist/SHA256SUMS").read_text(), expected)


if __name__ == "__main__":
    unittest.main()
