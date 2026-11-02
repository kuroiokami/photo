"""Standard macOS ICNS derivatives of the project artwork; no runtime dependency."""
from functools import lru_cache
from pathlib import Path
import struct
import subprocess
import tempfile

ICON_FILE = "PhotoIcon.icns"
MASTER = Path("Assets/AppIcon/PhotoIcon.png")
ICON_SIZES = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}


class IconError(ValueError):
    pass


def png_size(data):
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise IconError("Icon artwork must be a PNG.")
    return struct.unpack(">II", data[16:24])


def native(args):
    result = subprocess.run([str(a) for a in args], capture_output=True)
    if result.returncode:
        raise IconError(result.stderr.decode(errors="replace").strip())


@lru_cache(maxsize=2)
def compile_icon(master):
    width, height = png_size(master)
    if width != height or not 1024 <= width <= 4096 or master[25] not in (4, 6):
        raise IconError("Icon artwork must be square, 1024–4096 pixels, with an alpha channel.")
    with tempfile.TemporaryDirectory(prefix="photo-icon-") as folder:
        root = Path(folder)
        original = root / "Master.png"
        original.write_bytes(master)
        iconset = root / "PhotoIcon.iconset"
        iconset.mkdir()
        for name, size in ICON_SIZES.items():
            native(["/usr/bin/sips", "-z", size, size, original, "--out", iconset / name])
        target = root / ICON_FILE
        native(["/usr/bin/iconutil", "--convert", "icns", "--output", target, iconset])
        data = target.read_bytes()
    verify_icon(data)
    return data


@lru_cache(maxsize=4)
def verify_icon(data):
    if len(data) < 8 or data[:4] != b"icns" or struct.unpack(">I", data[4:8])[0] != len(data):
        raise IconError("App icon has an invalid ICNS header.")
    # Decode the actual container, not just the source filenames. Apple tools
    # can choose PNG or other supported ICNS encodings for individual sizes.
    with tempfile.TemporaryDirectory(prefix="photo-icon-check-") as folder:
        root = Path(folder)
        icon = root / ICON_FILE
        icon.write_bytes(data)
        iconset = root / "Verified.iconset"
        native(["/usr/bin/iconutil", "--convert", "iconset", "--output", iconset, icon])
        names = {p.name for p in iconset.iterdir()}
        if names != set(ICON_SIZES):
            raise IconError("App icon is missing a standard 1x/2x representation.")
        for name, size in ICON_SIZES.items():
            if png_size((iconset / name).read_bytes()) != (size, size):
                raise IconError("App icon contains an incorrect representation size.")
    return True
