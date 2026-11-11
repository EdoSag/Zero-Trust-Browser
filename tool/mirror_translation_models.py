#!/usr/bin/env python3
"""Mirrors Mozilla's Firefox Translations models for ZT Browser (B16).

ZT Browser translates pages on the phone with Firefox's translation engine
(Bergamot, MPL-2.0). Its language models come from Mozilla's model
registry; this copies the released ones into the "translation-models"
release of the ZT Browser repo, so phones download them from there and
never contact anyone else. Page text never leaves the phone either way.

Usage: mirror_translation_models.py OUT_DIR [PREVIOUS_MANIFEST]

Writes OUT_DIR/models.json (the manifest the app reads, signed by the
workflow) and the .gz model files, and OUT_DIR/changed.txt: the files that
differ from PREVIOUS_MANIFEST, so only those are uploaded again.
"""

import gzip
import hashlib
import json
import os
import sys
import time
import urllib.request

REGISTRY = (
    "https://storage.googleapis.com/"
    "moz-fx-translations-data--303e-prod-translations-data/db/models.json"
)
# Smaller and faster models first: they run on phones.
PREFERENCE = ["tiny", "base-memory", "base"]
PARTS = {"model": "model", "lexicalShortlist": "lex", "vocab": "vocab"}


def fetch(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return r.read()
        except Exception:  # noqa: BLE001 - retried, then raised
            if i == tries - 1:
                raise
            time.sleep(2 ** (i + 1))


def main():
    out = sys.argv[1]
    previous = {}
    if len(sys.argv) > 2 and os.path.exists(sys.argv[2]):
        try:
            previous = json.load(open(sys.argv[2])).get("models", {})
        except ValueError:
            previous = {}
    os.makedirs(out, exist_ok=True)
    registry = json.loads(fetch(REGISTRY))
    base = registry["baseUrl"].rstrip("/")
    models = {}
    changed = []
    # PAIRS=en-he,he-en limits the copy (for trying it locally).
    only = set(filter(None, os.environ.get("PAIRS", "").split(",")))
    for pair, entries in sorted(registry["models"].items()):
        if only and pair not in only:
            continue
        released = [e for e in entries if e.get("releaseStatus") == "Release"]
        if not released:
            continue
        released.sort(
            key=lambda e: PREFERENCE.index(e["architecture"])
            if e["architecture"] in PREFERENCE
            else len(PREFERENCE)
        )
        entry = released[0]
        files = {}
        for part, key in PARTS.items():
            info = entry["files"].get(part)
            if not info:
                break
            gz = fetch(f"{base}/{info['path']}")
            raw = gzip.decompress(gz)
            want = info.get("uncompressedHash")
            got = hashlib.sha256(raw).hexdigest()
            if want and want != got:
                raise SystemExit(f"{pair} {part}: hash mismatch")
            asset = f"{pair}.{key}.bin.gz"
            files[key] = {
                "asset": asset,
                # Mozilla's file name: tells the engine the model's precision.
                "name": info["path"].rsplit("/", 1)[-1].removesuffix(".gz"),
                "gzSize": len(gz),
                "size": len(raw),
                "sha256": got,
            }
            old = previous.get(pair, {}).get("files", {}).get(key, {})
            if old.get("sha256") != got:
                with open(os.path.join(out, asset), "wb") as f:
                    f.write(gz)
                changed.append(asset)
        else:
            models[pair] = {
                "from": entry["sourceLanguage"],
                "to": entry["targetLanguage"],
                "architecture": entry["architecture"],
                "files": files,
            }
            print(pair, entry["architecture"], sum(f["gzSize"] for f in files.values()))
    manifest = {
        "version": 1,
        "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": "Mozilla Firefox Translations models (MPL-2.0), "
        + "https://github.com/mozilla/translations",
        "models": models,
    }
    with open(os.path.join(out, "models.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    with open(os.path.join(out, "changed.txt"), "w") as f:
        f.write("\n".join(changed))
    print(f"{len(models)} models, {len(changed)} files changed")


if __name__ == "__main__":
    main()
