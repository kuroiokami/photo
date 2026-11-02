"""Committed-source package creation and mounted-payload verification."""
from contextlib import contextmanager
import json
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
from macos_bundle import (DEVELOPMENT_ID, LICENSES, PackageError, assemble, inventory,
                          rename_directory, run, sha256, verify_app)

INSTALL_TEXT = """Photo — local development package

This package is ad-hoc signed and has not been notarized by Apple.
It is for local installation checks, not a public beta download.

Install
1. Quit all running copies of Photo.
2. Drag Photo.app onto Applications.
3. Eject this disk image and open Photo from Applications.

Update
Quit Photo and replace the complete Photo.app. Keep the bundled preview helper
inside the app. Your saved reviews and decisions are kept separately from the app and stay
when you replace it. Development builds have separate settings from packaged
builds. Updating one packaged build to the next keeps its settings.

Licenses are in the Licenses folder and inside Photo.app/Contents/Resources/Legal.
A Developer ID signature, notarization and clean-Mac acceptance are still needed
before distributing a public beta. Do not disable macOS security to run a build.
"""


def export_commit(repo, revision, destination):
    commit = run(["git", "rev-parse", "--verify", "--end-of-options", revision + "^{commit}"], cwd=repo).decode().strip()
    archive = Path(destination).parent / "source.tar"
    run(["git", "archive", "--format=tar", "--output", archive, commit], cwd=repo)
    Path(destination).mkdir()
    with tarfile.open(archive) as source:
        for member in source.getmembers():
            parts = Path(member.name).parts
            if member.name.startswith("/") or ".." in parts or not (member.isfile() or member.isdir()):
                raise PackageError("Source export contains a link, special file or unsafe path.")
        source.extractall(destination)
    return commit


@contextmanager
def mounted_image(image):
    with tempfile.TemporaryDirectory(prefix="photo-dmg-check-") as folder:
        mount = Path(folder).resolve() / "Volume"
        mount.mkdir()
        attached = False
        try:
            raw = run(["/usr/bin/hdiutil", "attach", "-plist", "-readonly",
                       "-nobrowse", "-mountpoint", mount, image])
            attached = True
            response = plistlib.loads(raw)
            matches = [e for e in response.get("system-entities", []) if e.get("mount-point") and Path(e["mount-point"]).resolve() == mount]
            if len(matches) != 1:
                raise PackageError("Disk image did not mount at its private verification location.")
            yield mount
        finally:
            if attached:
                run(["/usr/bin/hdiutil", "detach", mount])


def verify_package(folder):
    folder = Path(folder)
    manifest_path = folder / "manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise PackageError("A regular package manifest is required.")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("schemaVersion") != 1 or manifest.get("publicReleaseReady") is not False:
        raise PackageError("Unknown or incorrectly labelled local package manifest.")
    image_name = manifest["diskImage"]["filename"]
    if Path(image_name).name != image_name or not image_name.endswith(".dmg"):
        raise PackageError("Invalid disk image name in manifest.")
    for path in (folder / image_name, folder / "SHA256SUMS"):
        if path.is_symlink() or not path.is_file():
            raise PackageError("Package image and checksums must be regular files.")
    expected_sums = f"{sha256(folder / image_name)}  {image_name}\n{sha256(manifest_path)}  manifest.json\n"
    if (folder / "SHA256SUMS").read_text() != expected_sums:
        raise PackageError("Package checksums differ.")
    if (folder / image_name).stat().st_size != manifest["diskImage"].get("bytes"):
        raise PackageError("Disk image size differs from its manifest.")
    if sha256(folder / image_name) != manifest["diskImage"]["sha256"]:
        raise PackageError("Disk image differs from its manifest.")
    app = folder / "Photo.app"
    if verify_app(app) != manifest["app"]:
        raise PackageError("App differs from its manifest.")
    if manifest["app"]["info"]["sourceKind"] != "commit" or manifest["app"]["info"]["sourceDirty"]:
        raise PackageError("A release package must use a committed source snapshot.")
    if manifest["app"]["info"]["bundleIdentifier"] == DEVELOPMENT_ID:
        raise PackageError("Packaged and development identities must differ.")
    if any(v["architectures"] != ["arm64"] for v in manifest["app"]["executables"].values()):
        raise PackageError("This package must be labelled and built for Apple silicon only.")
    image_info = plistlib.loads(run(["/usr/bin/hdiutil", "imageinfo", "-plist", folder / image_name]))
    if image_info.get("Format") != "UDZO":
        raise PackageError("The download must be a UDZO read-only compressed disk image.")
    run(["/usr/bin/hdiutil", "verify", folder / image_name])
    with mounted_image(folder / image_name) as mount:
        if verify_app(mount / "Photo.app") != manifest["app"]:
            raise PackageError("Mounted app differs from the staged app.")
        link = mount / "Applications"
        if not link.is_symlink() or os.readlink(link) != "/Applications":
            raise PackageError("The Applications shortcut is missing or changed.")
        expected_root = {"Photo.app", "Applications", "Install Photo.txt", "Licenses"}
        # Finder/volume metadata is generated by hdiutil, not shipped application content.
        visible_root = {p.name for p in mount.iterdir() if not p.name.startswith(".")}
        if visible_root != expected_root or sha256(mount / "Install Photo.txt") != manifest["installationGuideSHA256"]:
            raise PackageError("Disk image installation contents differ.")
        for name in LICENSES:
            if sha256(mount / "Licenses" / name) != manifest["app"]["files"][f"Contents/Resources/Legal/{name}"]:
                raise PackageError("Disk image licenses differ from the app licenses.")
    return manifest


def build_package(repo, revision, version, build, bundle_id, output):
    output = Path(output).absolute()
    if output.exists() or output.is_symlink() or any(p.suffix == ".app" for p in output.parents):
        raise PackageError("Choose a new package folder outside any app; existing packages are never overwritten.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="photo-source-") as source_folder:
        source = Path(source_folder) / "Source"
        commit = export_commit(repo, revision, source)
        scratch = Path(source_folder) / "Build"
        args = ["swift", "build", "--package-path", source, "--scratch-path", scratch, "-c", "release"]
        for product in ("Photo", "PhotoPreviewWorker"):
            subprocess.run([str(a) for a in args + ["--product", product]], check=True)
        binaries = Path(run(args + ["--show-bin-path"]).decode().strip())
        with tempfile.TemporaryDirectory(prefix=".photo-package-", dir=output.parent) as stage_folder:
            stage = Path(stage_folder) / "Package"
            stage.mkdir()
            app = stage / "Photo.app"
            receipt = assemble(app, binaries, source, version, build, bundle_id, commit)
            if any(v["architectures"] != ["arm64"] for v in receipt["executables"].values()):
                raise PackageError("Only an Apple silicon local package is implemented in this phase.")
            volume = Path(stage_folder) / "Volume"
            volume.mkdir()
            run(["/usr/bin/ditto", app, volume / "Photo.app"])
            (volume / "Applications").symlink_to("/Applications")
            (volume / "Install Photo.txt").write_text(INSTALL_TEXT, encoding="utf-8")
            shutil.copytree(app / "Contents/Resources/Legal", volume / "Licenses")
            image = stage / f"Photo-{version}-{build}-macos-arm64-local.dmg"
            run(["/usr/bin/hdiutil", "create", "-volname", f"Photo {version}", "-srcfolder", volume,
                 "-fs", "HFS+", "-format", "UDZO", image])
            manifest = dict(schemaVersion=1, publicReleaseReady=False, app=receipt,
                            installationGuideSHA256=hashlib.sha256(INSTALL_TEXT.encode()).hexdigest(),
                            diskImage=dict(filename=image.name, sha256=sha256(image), bytes=image.stat().st_size),
                            toolchain=run(["swift", "--version"]).decode().strip(),
                            checks=dict(sourceSnapshot="git-archive", signatures="ad-hoc",
                                        notarization="not-performed", gatekeeper="not-accepted-for-public-distribution",
                                        tests="run-separately-for-source-commit", minimumPlatform="declared-not-native-verified"))
            manifest_path = stage / "manifest.json"
            manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            (stage / "SHA256SUMS").write_text(f"{sha256(image)}  {image.name}\n{sha256(manifest_path)}  manifest.json\n")
            verify_package(stage)
            rename_directory(stage, output)
    return output
