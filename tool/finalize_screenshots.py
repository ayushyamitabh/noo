#!/usr/bin/env python3
"""Makes captured screenshots Play Store ready and reports anything that isn't.

Play wants JPEG or 24-bit PNG (no alpha), each side 320-3840 px, and the long
side at most twice the short side. The captured PNGs are 32-bit RGBA, so this
flattens them to RGB in place, then checks the dimensions.

  python3 tool/finalize_screenshots.py store_listing/screenshots
"""
import sys
from pathlib import Path

from PIL import Image


def main(directory):
    files = sorted(Path(directory).glob("*.png"))
    if not files:
        sys.exit("No PNGs found in %s" % directory)

    problems = 0
    for path in files:
        with Image.open(path) as im:
            im.load()
            rgb = Image.new("RGB", im.size, (255, 255, 255))
            rgb.paste(im, mask=im.getchannel("A") if "A" in im.getbands() else None)
        rgb.save(path, "PNG", optimize=True)

        w, h = rgb.size
        notes = []
        if min(w, h) < 320 or max(w, h) > 3840:
            notes.append("side outside 320-3840 px")
        if max(w, h) > 2 * min(w, h):
            notes.append("aspect ratio over 2:1")
        problems += bool(notes)
        print("%-32s %4dx%-4d %s" % (path.name, w, h, "; ".join(notes) or "ok"))

    print("\n%d screenshots, %d with problems" % (len(files), problems))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "store_listing/screenshots")
