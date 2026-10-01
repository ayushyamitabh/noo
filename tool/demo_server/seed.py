#!/usr/bin/env python3
"""Fills a throwaway Nextcloud with fake data for the Play Store screenshots.

Everything here is invented or procedurally generated (landscape "photos"
drawn with Pillow, tiny hand-built PDFs, made-up names), so nothing real -
and nothing with a licence or a face in it - can end up in a screenshot.

  python3 seed.py                    seed http://localhost (DEMO_BASE_URL)
  python3 seed.py --generate-only D  write the fake files under D, no server

On success the LAST line printed to stdout is `APP_PASSWORD=<token>` - an app
password for the demo user, which tool/screenshots.sh hands to the app so it
can start logged in without going through the browser login flow. All
progress output goes to stderr.
"""
import argparse
import io
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote

from PIL import Image, ImageDraw, ImageFilter

BASE = os.environ.get("DEMO_BASE_URL", "http://localhost").rstrip("/")
ADMIN = ("admin", os.environ.get("NEXTCLOUD_ADMIN_PASSWORD", "demo-admin-password"))
FILLER_MB = int(os.environ.get("DEMO_FILLER_MB", "300"))

# The account the screenshots are taken as, and a second user to share with.
USERS = {
    "Alex": ("alex-demo-pass", "Alex Morgan", "alex@example.com", "15 GB"),
    "Sam": ("sam-demo-pass", "Sam Rivera", "sam@example.com", "5 GB"),
}


def log(message):
    print(message, file=sys.stderr, flush=True)


# --------------------------------------------------------------- content ---

# (sky top, sky bottom, sun, far hills, mid hills, near hills)
PALETTES = [
    ((250, 176, 120), (255, 226, 170), (255, 250, 220), (152, 120, 150), (108, 90, 128), (62, 60, 96)),
    ((70, 130, 200), (190, 225, 245), (255, 255, 240), (110, 150, 170), (70, 118, 130), (40, 84, 90)),
    ((30, 40, 90), (240, 130, 110), (255, 220, 190), (90, 60, 110), (60, 44, 84), (30, 28, 56)),
    ((110, 180, 190), (230, 245, 235), (255, 245, 200), (130, 180, 150), (84, 140, 110), (44, 98, 76)),
    ((240, 150, 90), (255, 214, 150), (255, 240, 200), (200, 130, 90), (160, 96, 70), (110, 66, 56)),
    ((20, 24, 60), (70, 60, 120), (240, 240, 255), (50, 50, 100), (34, 36, 80), (18, 20, 50)),
    ((150, 200, 230), (245, 250, 255), (255, 255, 255), (170, 190, 210), (130, 156, 180), (90, 120, 150)),
    ((200, 120, 160), (250, 200, 190), (255, 235, 210), (170, 100, 140), (126, 78, 116), (80, 54, 90)),
]


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def landscape(seed, size=(1600, 1067)):
    """A soft, layered-hills landscape - reads as a photo at thumbnail size."""
    rnd = random.Random(seed)
    top, bottom, sun, far, mid, near = PALETTES[seed % len(PALETTES)]
    w, h = size
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        draw.line([(0, y), (w, y)], fill=_mix(top, bottom, min(1.0, y / (h * 0.75))))
    sx, sy, sr = rnd.randint(w // 5, 4 * w // 5), rnd.randint(h // 6, h // 3), rnd.randint(h // 12, h // 7)
    draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=sun)
    for base, amp, color in ((0.62, 0.10, far), (0.72, 0.13, mid), (0.84, 0.10, near)):
        phase = [rnd.uniform(0, math.tau) for _ in range(3)]
        freq = [rnd.uniform(1.0, 2.0), rnd.uniform(2.5, 4.0), rnd.uniform(5.0, 8.0)]
        weight = (1.0, 0.5, 0.2)
        pts = [(0, h)]
        for x in range(0, w + 8, 8):
            v = sum(wt * math.sin(x / w * math.tau * f + p) for wt, f, p in zip(weight, freq, phase))
            pts.append((x, int(h * base + h * amp * v / 1.7)))
        pts.append((w, h))
        draw.polygon(pts, fill=color)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    out = io.BytesIO()
    img.save(out, "JPEG", quality=86)
    return out.getvalue()


def pdf(title, lines):
    """A tiny but valid one-page PDF."""

    def esc(s):
        return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

    body = "BT /F1 26 Tf 72 720 Td (%s) Tj ET\n" % esc(title)
    for i, line in enumerate(lines):
        body += "BT /F1 12 Tf 72 %d Td (%s) Tj ET\n" % (680 - 20 * i, esc(line))
    stream = body.encode("latin-1", "replace")
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        b"/Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, obj in enumerate(objs, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + obj + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return bytes(out)


def text(body):
    return body.strip().encode("utf-8") + b"\n"


def video():
    """A short test-pattern clip if ffmpeg is around, else None (skipped)."""
    if not shutil.which("ffmpeg"):
        return None
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "clip.mp4")
        result = subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=duration=6:size=640x360:rate=24",
             "-pix_fmt", "yuv420p", path],
            capture_output=True,
        )
        if result.returncode != 0:
            return None
        with open(path, "rb") as f:
            return f.read()


def build_content():
    """(path, bytes) for everything the demo user owns, plus what to favorite/delete."""
    files = []

    def add(path, data):
        if data is not None:
            files.append((path, data))

    add("/Welcome.md", text("# Welcome\n\nYour files, everywhere you go."))
    add("/Vacation ideas.txt", text("Lisbon\nKyoto\nPatagonia\nIceland in winter"))

    add("/Documents/Project brief.pdf", pdf("Project brief", ["Goals for the quarter", "Milestones and owners", "Open questions"]))
    add("/Documents/Quarterly report.pdf", pdf("Quarterly report", ["Revenue up 12 percent", "Churn down 3 percent", "Hiring plan"]))
    add("/Documents/Meeting notes.md", text("# Meeting notes\n\n- Ship the beta on Friday\n- Review pricing\n- Book the offsite"))
    add("/Documents/Budget 2026.xlsx", os.urandom(24_000))
    add("/Documents/Contracts/Lease agreement.pdf", pdf("Lease agreement", ["Term: 12 months", "Rent due on the 1st"]))
    add("/Documents/Contracts/NDA - template.pdf", pdf("Mutual NDA", ["Standard template"]))

    trips = ["Lake sunrise", "Mountain pass", "Old town", "Beach day", "Desert road", "Forest trail", "City lights"]
    for i, name in enumerate(trips):
        add("/Trips/%s.jpg" % name, landscape(i + 1))
    add("/Trips/Trip itinerary.pdf", pdf("Trip itinerary", ["Day 1  Arrive and settle in", "Day 2  Old town walk", "Day 3  Coast day trip"]))

    for i in range(8):
        add("/Photos/Summer 2026/IMG_%04d.jpg" % (2041 + i), landscape(20 + i))
    add("/Photos/Summer 2026/Clip - hike.mp4", video())

    add("/Recipes/Pasta al limone.md", text("# Pasta al limone\n\nSpaghetti, lemon, butter, parmesan, black pepper."))
    add("/Recipes/Sourdough.md", text("# Sourdough\n\n500g flour, 350g water, 100g starter, 10g salt."))
    add("/Recipes/Shopping list.txt", text("Lemons\nParmesan\nFlour\nCoffee beans"))

    add("/Projects/Website redesign/Wireframes.pdf", pdf("Wireframes", ["Home", "Pricing", "Sign up"]))
    add("/Projects/Website redesign/Design tokens.json", text('{"radius": 12, "primary": "#2a6b50"}'))
    add("/Projects/Website redesign/notes.txt", text("Kickoff next Tuesday.\nCollect brand assets."))

    favorites = ["/Trips/Lake sunrise.jpg", "/Trips/Mountain pass.jpg", "/Documents/Project brief.pdf", "/Recipes/Sourdough.md"]

    # Created, then deleted - they end up in the Trash tab.
    trashed = [
        ("/Old draft.txt", text("Superseded draft.")),
        ("/Screenshot 2026-03-14.jpg", landscape(40, (1080, 1920))),
        ("/Receipts (old)/March.pdf", pdf("Receipt", ["March"])),
    ]
    return files, favorites, trashed


# ---------------------------------------------------------------- server ---


class ZeroStream:
    """`size` zero bytes, streamed - a big filler file without holding it in memory."""

    def __init__(self, size):
        self.size, self.pos = size, 0

    def __len__(self):
        return self.size

    def read(self, n=-1):
        n = self.size - self.pos if n is None or n < 0 else min(n, self.size - self.pos)
        self.pos += n
        return b"\0" * n


class Server:
    def __init__(self):
        import requests  # imported lazily so --generate-only needs no network libs

        self.requests = requests

    def _call(self, method, url, auth, **kw):
        headers = kw.pop("headers", {})
        headers.setdefault("OCS-APIRequest", "true")
        return self.requests.request(method, url, auth=auth, headers=headers, timeout=600, **kw)

    def wait_ready(self):
        log("Waiting for Nextcloud to finish installing (first start takes a minute or two)...")
        deadline = time.time() + 600
        while time.time() < deadline:
            try:
                r = self.requests.get(BASE + "/status.php", timeout=5)
                if r.ok and r.json().get("installed") and not r.json().get("maintenance"):
                    return
            except Exception:
                pass
            time.sleep(3)
        sys.exit("Nextcloud did not become ready in time")

    def ocs(self, method, path, auth, **kw):
        r = self._call(method, BASE + path, auth, params={"format": "json"}, **kw)
        try:
            return r.json()["ocs"]
        except Exception:
            return {"meta": {"statuscode": r.status_code}, "data": {}}

    def create_user(self, user, password, display, email, quota):
        res = self.ocs(
            "POST", "/ocs/v1.php/cloud/users", ADMIN,
            data={"userid": user, "password": password, "displayName": display, "email": email, "quota": quota},
        )
        code = res["meta"]["statuscode"]
        if code not in (100, 200, 102):  # 102 = already exists
            sys.exit("Could not create user %s: %s" % (user, res))

    def dav(self, method, user, path, **kw):
        auth = (user, USERS[user][0])
        url = "%s/remote.php/dav/files/%s%s" % (BASE, user, quote(path))
        return self._call(method, url, auth, **kw)

    def mkdirs(self, user, path):
        built = ""
        for part in [p for p in path.split("/") if p]:
            built += "/" + part
            self.dav("MKCOL", user, built)

    def put(self, user, path, data):
        parent = path.rsplit("/", 1)[0]
        if parent:
            self.mkdirs(user, parent)
        r = self.dav("PUT", user, path, data=data)
        if r.status_code not in (200, 201, 204):
            sys.exit("PUT %s failed: %s %s" % (path, r.status_code, r.text[:200]))

    def favorite(self, user, path):
        body = (
            '<?xml version="1.0"?><d:propertyupdate xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">'
            "<d:set><d:prop><oc:favorite>1</oc:favorite></d:prop></d:set></d:propertyupdate>"
        )
        self.dav("PROPPATCH", user, path, data=body, headers={"Content-Type": "application/xml"})

    def delete(self, user, path):
        self.dav("DELETE", user, path)

    def share(self, user, path, share_type, share_with=None, permissions=31):
        data = {"path": path, "shareType": share_type, "permissions": permissions}
        if share_with:
            data["shareWith"] = share_with
        auth = (user, USERS[user][0])
        self.ocs("POST", "/ocs/v2.php/apps/files_sharing/api/v1/shares", auth, data=data)

    def app_password(self, user):
        auth = (user, USERS[user][0])
        res = self.ocs("GET", "/ocs/v2.php/core/getapppassword", auth)
        token = (res.get("data") or {}).get("apppassword")
        if not token:
            sys.exit("Could not get an app password for %s: %s" % (user, res))
        return token


def seed_server():
    server = Server()
    server.wait_ready()

    for user, (password, display, email, quota) in USERS.items():
        log("Creating user %s" % user)
        server.create_user(user, password, display, email, quota)

    files, favorites, trashed = build_content()
    log("Uploading %d files as Alex" % len(files))
    for path, data in files:
        server.put("Alex", path, data)
    if FILLER_MB > 0:
        log("Uploading a %d MB filler file so the storage quota isn't empty" % FILLER_MB)
        server.put("Alex", "/Backups/Laptop backup.zip", ZeroStream(FILLER_MB * 1024 * 1024))

    for path in favorites:
        server.favorite("Alex", path)

    log("Creating shares")
    server.share("Alex", "/Trips", 0, "Sam", permissions=31)
    server.share("Alex", "/Documents/Project brief.pdf", 3, permissions=1)
    server.put("Sam", "/Team notes/Roadmap.md", text("# Roadmap\n\nQ3: beta. Q4: launch."))
    server.put("Sam", "/Team notes/Standup.md", text("Daily standup at 9:30."))
    server.share("Sam", "/Team notes", 0, "Alex", permissions=31)
    # Sam edits inside the folder Alex shared - gives the Activity feed a second author.
    server.put("Sam", "/Trips/Suggestions.txt", text("Add the coast road stop!"))

    log("Filling the trash")
    for path, data in trashed:
        server.put("Alex", path, data)
    for path, _ in trashed:
        server.delete("Alex", path)
    server.delete("Alex", "/Receipts (old)")

    token = server.app_password("Alex")
    print("APP_PASSWORD=" + token, flush=True)


def generate_only(target):
    files, favorites, trashed = build_content()
    for path, data in files + trashed:
        dest = os.path.join(target, "Alex" + path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data)
    log("Wrote %d files under %s (favorites: %d)" % (len(files) + len(trashed), target, len(favorites)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--generate-only", metavar="DIR", help="write the fake files locally instead of seeding a server")
    args = parser.parse_args()
    if args.generate_only:
        generate_only(args.generate_only)
    else:
        seed_server()
