#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""
Fetch free-licensed cat photos from Wikimedia Commons and convert them for the watch (410x502 baseline JPEG,
cropped to fill). Writes ../images/cat_NN.jpg and ../CREDITS.md. Not part of the build; run it once and commit the
output:

    python3 -I tools/fetch_cats.py [--count 50]

macOS only (uses `curl` for HTTPS and `sips` for image conversion, so no extra Python packages are needed).
"""
import argparse
import html
import json
import re
import shutil
import subprocess
import tempfile
import time
import urllib.parse
from pathlib import Path

USER_AGENT = "esp32-watch-cat-fetch/1.0 (personal hobby project)"
API = "https://commons.wikimedia.org/w/api.php"
# Searched including subcategories (CirrusSearch `deepcat:`), which returns file info in the same requests
CATEGORIES = ["Quality images of cats", "Featured pictures of cats"]
SCREEN_W, SCREEN_H = 410, 502
JPEG_QUALITY = 75
THUMB_WIDTH = 1000
LICENSE_OK = re.compile(r"^(CC0|Public domain|PD.*|CC BY(-SA)? \d\.\d.*)$", re.IGNORECASE)

COMPONENT_DIR = Path(__file__).resolve().parent.parent


def curl(url: str, out: Path | None = None) -> bytes:
    # --retry also covers HTTP 429 (rate limited) and honours the server's Retry-After
    cmd = ["curl", "-sfL", "--retry", "6", "--retry-max-time", "600", "-A", USER_AGENT, url]
    if out is not None:
        cmd += ["-o", str(out)]
    return subprocess.run(cmd, check=True, capture_output=True).stdout


def api(**params) -> dict:
    params["format"] = "json"
    time.sleep(1)       # Be gentle with the API (it rate-limits clients)
    return json.loads(curl(API + "?" + urllib.parse.urlencode(params)))


def category_images(category: str) -> list[dict]:
    """imageinfo (with license metadata and a THUMB_WIDTH thumbnail) for all files in a category tree."""
    infos = []
    cont = {}
    while True:
        data = api(action="query", generator="search", gsrsearch=f'deepcat:"{category}"', gsrnamespace=6,
                   gsrlimit=50, prop="imageinfo", iiprop="url|size|mime|extmetadata", iiurlwidth=THUMB_WIDTH, **cont)
        for page in data.get("query", {}).get("pages", {}).values():
            if "imageinfo" in page:
                info = page["imageinfo"][0]
                info["title"] = page["title"]
                infos.append(info)
        if "continue" not in data:
            break
        cont = data["continue"]
    return infos


def meta(info: dict, key: str) -> str:
    value = info.get("extmetadata", {}).get(key, {}).get("value", "")
    return html.unescape(re.sub(r"<[^>]+>", "", value)).strip()


def convert(src: Path, dst: Path, w: int, h: int) -> None:
    """Scale so the image covers the screen, then center-crop to exactly the screen size."""
    scale = max(SCREEN_W / w, SCREEN_H / h)
    new_w, new_h = max(SCREEN_W, round(w * scale)), max(SCREEN_H, round(h * scale))
    subprocess.run(["sips", "-z", str(new_h), str(new_w), str(src), "--out", str(dst)], check=True, capture_output=True)
    subprocess.run(["sips", "-c", str(SCREEN_H), str(SCREEN_W), "-s", "format", "jpeg",
                    "-s", "formatOptions", str(JPEG_QUALITY), str(dst), "--out", str(dst)],
                   check=True, capture_output=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--count", type=int, default=50)
    args = parser.parse_args()

    infos = {}
    for category in CATEGORIES:
        for info in category_images(category):
            infos[info["title"]] = info
    print(f"{len(infos)} files found")

    candidates = []
    for info in infos.values():
        license_name = meta(info, "LicenseShortName")
        if info.get("mime") != "image/jpeg" or not LICENSE_OK.match(license_name):
            continue
        if info["width"] < SCREEN_W or info["height"] < SCREEN_H or "thumburl" not in info:
            continue
        candidates.append(info)
    # Prefer photos shaped like the (portrait) screen, so cropping loses as little as possible
    target = SCREEN_W / SCREEN_H
    candidates.sort(key=lambda i: (abs(i["width"] / i["height"] - target), i["title"]))
    chosen = candidates[:args.count]
    print(f"{len(candidates)} usable, taking {len(chosen)}")

    images_dir = COMPONENT_DIR / "images"
    if images_dir.exists():
        shutil.rmtree(images_dir)
    images_dir.mkdir()

    credits = [
        "# Cat photo credits",
        "",
        "Photos from [Wikimedia Commons](https://commons.wikimedia.org), cropped and resized to 410x502 for the "
        "watch by `tools/fetch_cats.py`. Each photo keeps its original license.",
        "",
        "| File | Photo | Author | License |",
        "|---|---|---|---|",
    ]
    total = 0
    with tempfile.TemporaryDirectory() as download_dir:
        for n, info in enumerate(chosen, start=1):
            name = f"cat_{n:02d}.jpg"
            raw = Path(download_dir) / f"raw_{n:02d}.jpg"
            curl(info["thumburl"], raw)
            time.sleep(1)
            convert(raw, images_dir / name, info["thumbwidth"], info["thumbheight"])
            total += (images_dir / name).stat().st_size
            title = info["title"].removeprefix("File:")
            author = meta(info, "Artist").replace("|", "/").replace("\n", " ") or "unknown"
            credits.append(f"| {name} | [{title}]({info['descriptionurl']}) | {author} | {meta(info, 'LicenseShortName')} |")
            print(f"{name}: {title}")

    (COMPONENT_DIR / "CREDITS.md").write_text("\n".join(credits) + "\n")
    print(f"Total: {total / 1024:.0f} KB for {len(chosen)} images")


if __name__ == "__main__":
    main()
