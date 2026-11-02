"""Shared macOS app assembly, verification and safe local replacement (stdlib only)."""
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid

DEVELOPMENT_ID = "com.kuroiokami.photo.development"
RELEASE_ID = "com.kuroiokami.photo"
RESOURCE_BUNDLE = "Photo_PhotoUI.bundle"
LICENSES = ("LICENSE-MIT", "LICENSE-APACHE", "NOTICE")


class PackageError(Exception):
    pass


def run(args, cwd=None):
    completed = subprocess.run([str(a) for a in args], cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    if completed.returncode:
        raise PackageError(f"{args[0]} failed: {completed.stderr.decode(errors='replace').strip()}")
    return completed.stdout


def validate_version(version, build, bundle_id):
    number = r"(?:0|[1-9][0-9]*)"
    if len(version) > 64 or not re.fullmatch(rf"{number}\.{number}\.{number}", version):
        raise PackageError("Version must contain three numbers, for example 0.1.0.")
    if not re.fullmatch(r"[1-9][0-9]{0,8}", build):
        raise PackageError("Build must be a positive integer with at most nine digits.")
    if len(bundle_id) > 255 or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id):
        raise PackageError("Use a reverse-DNS bundle identifier.")


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inventory(root):
    """Relative file hashes; reject links/special files inside executable bundles."""
    result = {}
    for path in sorted(Path(root).rglob("*")):
        if path.is_symlink() or (not path.is_file() and not path.is_dir()):
            raise PackageError("App bundles must contain only regular files and directories.")
        if path.is_file():
            result[path.relative_to(root).as_posix()] = sha256(path)
    return result


def read_info(app):
    try:
        if Path(app).is_symlink() or not Path(app).is_dir():
            raise ValueError()
        path = Path(app) / "Contents/Info.plist"
        if path.is_symlink():
            raise ValueError()
        value = plistlib.loads(path.read_bytes())
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise PackageError("The app has no readable regular Info.plist.") from error


def assemble(app, binaries, source, version, build, bundle_id, revision,
             source_kind="commit", source_dirty=False):
    validate_version(version, build, bundle_id)
    app, binaries, source = Path(app), Path(binaries), Path(source)
    if app.exists() or app.is_symlink():
        raise PackageError("App staging must be new and empty.")
    resources = app / "Contents/Resources"
    (app / "Contents/MacOS").mkdir(parents=True)
    resources.mkdir()
    for name in ("Photo", "PhotoPreviewWorker"):
        binary = binaries / name
        if binary.is_symlink() or not binary.is_file() or not os.access(binary, os.X_OK):
            raise PackageError(f"Missing regular executable: {name}")
        shutil.copy2(binary, app / "Contents/MacOS" / name)
    bundle = binaries / RESOURCE_BUNDLE
    if not bundle.is_dir() or bundle.is_symlink():
        raise PackageError("The SwiftPM photo resource bundle is missing.")
    inventory(bundle)
    shutil.copytree(bundle, resources / RESOURCE_BUNDLE)
    legal = resources / "Legal"
    legal.mkdir()
    for name in LICENSES:
        if (source / name).is_symlink() or not (source / name).is_file():
            raise PackageError(f"Missing regular license file: {name}")
        shutil.copy2(source / name, legal / name)
    info = dict(CFBundleIdentifier=bundle_id, CFBundleName="Photo", CFBundleDisplayName="Photo",
                CFBundleExecutable="Photo", CFBundlePackageType="APPL", CFBundleVersion=build,
                CFBundleShortVersionString=version, LSMinimumSystemVersion="14.0",
                NSHighResolutionCapable=True, NSPrincipalClass="NSApplication")
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    build_info = dict(sourceCommit=revision, version=version, build=build,
                      bundleIdentifier=bundle_id, signing="ad-hoc", notarized=False,
                      sourceKind=source_kind, sourceDirty=source_dirty)
    (resources / "BuildInfo.json").write_text(json.dumps(build_info, indent=2) + "\n")
    # Explicit inside-out signing. --deep is used only for verification.
    run(["/usr/bin/codesign", "--force", "--sign", "-", app / "Contents/MacOS/PhotoPreviewWorker"])
    run(["/usr/bin/codesign", "--force", "--sign", "-", app])
    return verify_app(app)


def verify_app(app):
    app = Path(app)
    info = read_info(app)
    files = inventory(app)
    try:
        validate_version(info["CFBundleShortVersionString"], info["CFBundleVersion"], info["CFBundleIdentifier"])
        if info["CFBundleExecutable"] != "Photo" or info["LSMinimumSystemVersion"] != "14.0":
            raise ValueError()
        build_info = json.loads((app / "Contents/Resources/BuildInfo.json").read_text())
        if (build_info["version"], build_info["build"], build_info["bundleIdentifier"]) != (
                info["CFBundleShortVersionString"], info["CFBundleVersion"], info["CFBundleIdentifier"]):
            raise ValueError()
        if not re.fullmatch(r"[0-9a-f]{40}", build_info["sourceCommit"]):
            raise ValueError()
        if build_info["sourceKind"] not in ("commit", "working-tree") or not isinstance(build_info["sourceDirty"], bool):
            raise ValueError()
        if build_info["signing"] != "ad-hoc" or build_info["notarized"] is not False:
            raise ValueError()
    except (KeyError, OSError, ValueError, TypeError) as error:
        raise PackageError("App version, identity or build receipt is invalid.") from error
    for name in LICENSES:
        if f"Contents/Resources/Legal/{name}" not in files:
            raise PackageError("A required license or notice is missing.")
    resource = app / "Contents/Resources" / RESOURCE_BUNDLE
    for name in ("coast.png", "dawn.png", "dusk.png", "PROVENANCE.md"):
        if len(list(resource.rglob(name))) != 1:
            raise PackageError(f"Missing or ambiguous bundled resource: {name}")
    executables = {}
    for name in ("Photo", "PhotoPreviewWorker"):
        path = app / "Contents/MacOS" / name
        if not path.is_file() or not os.access(path, os.X_OK):
            raise PackageError(f"Missing executable: {name}")
        run(["/usr/bin/codesign", "--verify", "--strict", path])
        # codesign writes its description to stderr; inspect using a separate call below.
        description = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(path)],
                                     capture_output=True, check=True).stderr.decode()
        if "Signature=adhoc" not in description:
            raise PackageError("This foundation verifies local ad-hoc packages only.")
        architectures = run(["/usr/bin/lipo", "-archs", path]).decode().split()
        if not architectures or not set(architectures) <= {"arm64", "x86_64"}:
            raise PackageError("Unsupported executable architecture.")
        commands = run(["/usr/bin/otool", "-l", path]).decode()
        minimums = re.findall(r"\bminos\s+([0-9.]+)", commands)
        if len(minimums) != len(architectures) or any(value != "14.0" for value in minimums):
            raise PackageError("Executable deployment target differs from macOS 14.0.")
        uuid_text = run(["/usr/bin/dwarfdump", "--uuid", path]).decode()
        uuids = {arch: value for value, arch in re.findall(r"UUID: ([0-9A-Fa-f-]+) \((arm64|x86_64)\)", uuid_text)}
        if set(uuids) != set(architectures):
            raise PackageError("Executable build UUID is missing.")
        executables[name] = dict(sha256=sha256(path), architectures=architectures,
                                 minimumOS=minimums[0], uuids=uuids)
    if executables["Photo"]["architectures"] != executables["PhotoPreviewWorker"]["architectures"]:
        raise PackageError("App and preview helper architectures differ.")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    return dict(info=build_info, files=files, executables=executables)


def running_inside(app, listing):
    prefix = str(Path(app).resolve()) + os.sep
    for line in listing.splitlines():
        columns = line.strip().split(None, 1)
        if len(columns) == 2 and str(Path(columns[1]).resolve()).startswith(prefix):
            return True
    return False


def require_stopped(app):
    listing = run(["/bin/ps", "-A", "-o", "pid=,comm="]).decode()
    if running_inside(app, listing):
        raise PackageError("Quit Photo before replacing this app. The installed copy is still running.")


def rename_directory(source, destination, swap=False):
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    # Darwin stdio.h: RENAME_SWAP=2; RENAME_EXCL=4. Never overwrite by fallback.
    if rename(os.fsencode(source), os.fsencode(destination), 2 if swap else 4):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))


def install_bundle(source, destination):
    source = Path(source).absolute()
    destination = Path(destination).absolute()
    if source.is_symlink() or destination.is_symlink() or destination.suffix != ".app":
        raise PackageError("Choose a regular .app destination, not a symbolic link.")
    source = source.resolve()
    destination = destination.parent.resolve() / destination.name
    if source == destination or source in destination.parents or destination in source.parents:
        raise PackageError("Source app and installation folder must be separate.")
    if any(parent.suffix == ".app" for parent in destination.parents):
        raise PackageError("Do not install an app inside another app.")
    expected = verify_app(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Serialize this installer's writers; Finder updates should also be performed only after Quit.
    with (destination.parent / ".photo-install.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        require_stopped(destination)
        if destination.exists() and read_info(destination).get("CFBundleIdentifier") != expected["info"]["bundleIdentifier"]:
            raise PackageError("The destination belongs to a different app or build identity.")
        folder = Path(tempfile.mkdtemp(prefix=".photo-install-", dir=destination.parent))
        staged = folder / "Photo.app"
        exchanged = False
        try:
            run(["/usr/bin/ditto", source, staged])
            if verify_app(staged) != expected:
                raise PackageError("The staged app differs from the verified source.")
            require_stopped(destination)
            backup = None
            if destination.exists():
                if read_info(destination).get("CFBundleIdentifier") != expected["info"]["bundleIdentifier"]:
                    raise PackageError("Destination identity changed during installation.")
                backup = destination.parent / (destination.stem + ".previous-" + uuid.uuid4().hex + ".app")
                rename_directory(staged, destination, swap=True)
                exchanged = True
                try:
                    rename_directory(staged, backup)
                except OSError as error:
                    raise PackageError(f"New app installed; previous app retained in {staged}") from error
            else:
                rename_directory(staged, destination)
            return backup
        finally:
            # After exchange, staged may be the only surviving copy of the old
            # app. Never delete that container if backup naming failed.
            if not exchanged or not staged.exists():
                shutil.rmtree(folder)
