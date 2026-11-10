#!/usr/bin/env python3
"""Builds assets/blocklist/blocklist.txt from EasyList, EasyPrivacy and the
EasyList Cookie List.

ZT Browser blocks requests by host name (like Brave's and DuckDuckGo's
network blocking), so it keeps only the network rules that name a whole host:

    ||ads.example.com^                -> blocked everywhere
    ||ads.example.com^$third-party    -> blocked when loaded by another site

and hides page elements with plain CSS selectors ("cosmetic" rules):

    ##.ad-box                         -> hidden on every site
    example.com##.cookie-banner       -> hidden on example.com
    example.com#@#.ad-box             -> generic hiding off on example.com

Rules with paths, wildcards, scriptlets or extended selectors are skipped.

EasyList, EasyPrivacy and the EasyList Cookie List are by The EasyList
authors (https://easylist.to), dual licensed GPL-3.0-or-later and
CC BY-SA 3.0. The generated list is shipped under CC BY-SA 3.0 with that
credit (see assets/blocklist/LICENSE).

Run it with a checkout of https://github.com/easylist/easylist:

    git clone --depth 1 https://github.com/easylist/easylist.git /tmp/easylist
    python3 -I tool/update_blocklist.py /tmp/easylist [output file]

The weekly "Blocklist" workflow runs the same, signs the result and
publishes it, so the app updates its list without an app update.
"""
import os
import re
import subprocess
import sys

NETWORK = [
    "easylist/easylist_adservers.txt",
    "easylist/easylist_adservers_popup.txt",
    "easyprivacy/easyprivacy_trackingservers.txt",
    "easyprivacy/easyprivacy_trackingservers_admiral.txt",
    "easyprivacy/easyprivacy_trackingservers_general.txt",
    "easyprivacy/easyprivacy_trackingservers_international.txt",
    "easyprivacy/easyprivacy_trackingservers_mining.txt",
    "easyprivacy/easyprivacy_trackingservers_notifications.txt",
    "easyprivacy/easyprivacy_trackingservers_thirdparty.txt",
]

# Element hiding: empty ad boxes and cookie banners.
COSMETIC = [
    "easylist/easylist_general_hide.txt",
    "easylist/easylist_specific_hide.txt",
    "easylist/easylist_allowlist_general_hide.txt",
    "easylist_cookie/easylist_cookie_general_hide.txt",
    "easylist_cookie/easylist_cookie_specific_hide.txt",
    "easylist_cookie/easylist_cookie_international_specific_hide.txt",
    "easylist_cookie/easylist_cookie_allowlist_general_hide.txt",
]

RULE = re.compile(r"^\|\|([a-z0-9][a-z0-9.-]*\.[a-z0-9-]+)\^(?:\$(.*))?$")
HOST_OPTIONS = {"", "third-party", "3p", "all", "document", "popup",
                "document,popup", "popup,third-party", "third-party,popup"}
DOMAIN = re.compile(r"^[a-z0-9][a-z0-9.-]*\.[a-z0-9-]+$")

# Selectors a browser understands as plain CSS. Anything with adblocker
# extensions (:-abp-has, :has-text, :xpath, :style ...) is left out, since
# one bad selector would void the whole rule it is grouped in.
SELECTOR_CHARS = re.compile(r"^[A-Za-z0-9 _\-#.\[\]=\"'^$*~|>+:(),]+$")
SAFE_PSEUDO = re.compile(
    r":(?!(?:not|has|is|where|first-child|last-child|nth-child|nth-of-type|"
    r"first-of-type|last-of-type|only-child|empty|root)\b)[a-z-]+")


def plain_css(sel: str) -> bool:
    if not sel or len(sel) > 300 or "{" in sel or "}" in sel:
        return False
    if not SELECTOR_CHARS.match(sel):
        return False
    if SAFE_PSEUDO.search(sel.replace("::", ":")):
        return False
    # Balanced brackets and quotes, or the CSS parser drops the group.
    if sel.count("(") != sel.count(")") or sel.count("[") != sel.count("]"):
        return False
    if sel.count('"') % 2 or sel.count("'") % 2:
        return False
    return True


def network(root: str) -> tuple[set[str], set[str]]:
    everywhere: set[str] = set()
    third_party: set[str] = set()
    for rel in NETWORK:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            print(f"skipping missing {rel}", file=sys.stderr)
            continue
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = RULE.match(line.strip().lower())
                if not m:
                    continue
                host, opts = m.group(1), (m.group(2) or "")
                if opts not in HOST_OPTIONS:
                    continue
                if "third-party" in opts or opts == "3p":
                    third_party.add(host)
                else:
                    everywhere.add(host)
    return everywhere, third_party - everywhere


def cosmetic(root: str):
    generic: set[str] = set()
    except_generic: set[str] = set()
    site: dict[str, set[str]] = {}
    for rel in COSMETIC:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            print(f"skipping missing {rel}", file=sys.stderr)
            continue
        with open(path, encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("!"):
                    continue
                if "#@#" in line:
                    domains, _, sel = line.partition("#@#")
                    # An exception for one selector turns generic hiding
                    # off on those domains: safe, if a little generous.
                    for d in domains.lower().split(","):
                        if DOMAIN.match(d):
                            except_generic.add(d)
                    continue
                if "##" not in line or "#?#" in line or "#$#" in line:
                    continue
                domains, _, sel = line.partition("##")
                sel = sel.strip()
                if not plain_css(sel):
                    continue
                if not domains:
                    generic.add(sel)
                    continue
                names = domains.lower().split(",")
                if any(n.startswith("~") for n in names):
                    continue
                for d in names:
                    if DOMAIN.match(d):
                        site.setdefault(d, set()).add(sel)
    return generic, except_generic, site


def main(root: str, out: str) -> None:
    everywhere, third_party = network(root)
    generic, except_generic, site = cosmetic(root)
    try:
        rev = subprocess.check_output(
            ["git", "-C", root, "log", "-1", "--format=%h %cs"], text=True).strip()
    except Exception:  # noqa: BLE001
        rev = "unknown"
    try:
        # Commit time in UTC: the app only takes a list newer than its own.
        date = subprocess.check_output(
            ["git", "-C", root, "log", "-1", "--format=%cd",
             "--date=format-local:%Y-%m-%dT%H:%M"], text=True,
            env={**os.environ, "TZ": "UTC"}).strip()
    except Exception:  # noqa: BLE001
        date = "1970-01-01T00:00"

    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("# ZT Browser blocklist, format 1.\n")
        f.write("# From EasyList, EasyPrivacy and the EasyList Cookie List\n")
        f.write("# (https://easylist.to) by The EasyList authors, CC BY-SA 3.0.\n")
        f.write(f"# Generated by tool/update_blocklist.py from easylist/easylist {rev}.\n")
        f.write(f"# list-date: {date}\n")
        f.write("# !hosts: '<host>' blocked everywhere, '<host> 3p' only on other sites.\n")
        f.write("# !hide: CSS selectors hidden on every site. Lines starting with # are\n")
        f.write("# comments only up to !hosts; in sections they are CSS id selectors.\n")
        f.write("# !hide-off: sites where !hide does not apply.\n")
        f.write("# !site-hide: '<domain> <selector>' hidden on that domain only.\n")
        f.write("!hosts\n")
        for h in sorted(everywhere):
            f.write(h + "\n")
        for h in sorted(third_party):
            f.write(h + " 3p\n")
        f.write("!hide\n")
        for s in sorted(generic):
            f.write(s + "\n")
        f.write("!hide-off\n")
        for d in sorted(except_generic):
            f.write(d + "\n")
        f.write("!site-hide\n")
        for d in sorted(site):
            for s in sorted(site[d]):
                f.write(f"{d} {s}\n")
    n_site = sum(len(v) for v in site.values())
    print(f"{len(everywhere)} hosts blocked everywhere, {len(third_party)} on "
          f"other sites only, {len(generic)} generic and {n_site} site "
          f"selectors on {len(site)} domains -> {out}")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.join(here, "..", "assets", "blocklist", "blocklist.txt")
    main(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else default)
