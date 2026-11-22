#!/usr/bin/env python3
"""Builds the phishing and malware list ZT Browser warns with (B-1).

Sources, both free to share:

  * Phishing.Database by Mitchell Krog and Nissar Chababy (MIT),
    phishing-domains-ACTIVE.txt: phishing sites still online.
  * URLhaus by abuse.ch (CC0), hostfile: hosts serving malware now.

Whole sites that host user pages (docs.google.com, telegra.ph...) turn up
in these lists because one page on them was bad. Warning on all of
docs.google.com would be wrong, so an entry is dropped when its own site
(its registrable domain, by the Public Suffix List) is one of the most
visited sites on the web (Tranco list, or any "rank,domain" CSV). Pages on
hosting platforms stay: the Public Suffix List makes evil.github.io its own
site, and a popular site with many listed sub-sites (x.000webhostapp.com,
y.weebly.com) is a platform whose users' pages are kept.

The phone never sends the address it checks anywhere: the app downloads
the whole list and looks hosts up locally. The list holds hashes, not
names: the first 8 bytes of SHA-256 of each host, sorted as signed 64-bit
numbers, so lookups are a binary search.

File (before gzip), a text header ending in an empty line, then binary:

    # ZT Browser safety list, format 1.
    # list-date: 2026-11-22T04:17
    # phishing: <n>
    # malware: <m>
    <empty line>
    <n big-endian int64 hashes, sorted> <m big-endian int64 hashes, sorted>

Usage:

    python3 -I tool/update_safety_list.py PHISHING URLHAUS PSL TOP OUT
"""

import datetime
import hashlib
import re
import struct
import sys

HEADER = '# ZT Browser safety list, format 1.'

# How many of the most visited sites are never warned about as a whole.
TOP_SITES = 20000

# Kept out whatever the top list says (it could fail to download).
NEVER = {
    'google.com', 'youtube.com', 'gmail.com', 'microsoft.com', 'live.com',
    'office.com', 'apple.com', 'icloud.com', 'amazon.com', 'facebook.com',
    'instagram.com', 'whatsapp.com', 'twitter.com', 'x.com', 'github.com',
    'gitlab.com', 'dropbox.com', 'wikipedia.org', 'telegra.ph', 't.me',
    'linkedin.com', 'zerotrust.bz', 'cloudflare.com', 'mozilla.org',
}

_HOST = re.compile(r'^[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?(\.[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?)+$')
_IP = re.compile(r'^\d{1,3}(\.\d{1,3}){3}$')

# Hosts that say "nothing" in hosts files.
_SKIP = {'localhost', 'localhost.localdomain', 'local', '0.0.0.0', '127.0.0.1'}


def clean(host):
    h = host.strip().lower().rstrip('.')
    if h.startswith('www.'):
        h = h[4:]
    if h in _SKIP or not (_HOST.match(h) or _IP.match(h)):
        return None
    return h


def read_phishing(path):
    out = set()
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if line:
                h = clean(line)
                if h:
                    out.add(h)
    return out


def read_hostfile(path):
    """A hosts file ("127.0.0.1 host") or a plain list of hosts."""
    out = set()
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            h = clean(parts[-1])
            if h:
                out.add(h)
    return out


class Suffixes:
    """The Public Suffix List (ICANN and private parts)."""

    def __init__(self, path):
        self.rules, self.wild, self.exc = set(), set(), set()
        with open(path, encoding='utf-8') as f:
            for line in f:
                r = line.strip().lower()
                if not r or r.startswith('//'):
                    continue
                r = r.split()[0]
                if r.startswith('!'):
                    self.exc.add(r[1:])
                elif r.startswith('*.'):
                    self.wild.add(r[2:])
                else:
                    self.rules.add(r)

    def suffix_len(self, labels):
        """How many trailing labels are the public suffix."""
        best = 1
        for i in range(len(labels)):
            cand = '.'.join(labels[i:])
            n = len(labels) - i
            if cand in self.exc:
                return n - 1
            if cand in self.rules:
                best = max(best, n)
            if i + 1 < len(labels) and '.'.join(labels[i + 1:]) in self.wild:
                best = max(best, n)
        return best

    def site(self, host):
        """The registrable domain of host, or None for a bare suffix."""
        if _IP.match(host):
            return host
        labels = host.split('.')
        n = self.suffix_len(labels)
        if n >= len(labels):
            return None
        return '.'.join(labels[-(n + 1):])


def read_top(path, limit):
    top = set()
    if not path or path == '-':
        return top
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) < 2:
                continue
            d = clean(parts[1])
            if d:
                top.add(d)
            if len(top) >= limit:
                break
    return top


# A popular site with at least this many listed sub-sites hosts its users'
# pages (squarespace.com, weebly.com...): those pages stay listed.
PLATFORM_MIN = 20


def keep(hosts, psl, top):
    sites = {h: psl.site(h) for h in hosts}
    subs = {}
    for h, site in sites.items():
        if site and site != h:
            subs[site] = subs.get(site, 0) + 1
    out = set()
    for h, site in sites.items():
        if site is None:
            continue
        if site in top or site in NEVER:
            # Never the popular site itself; its sub-sites only when it is a
            # platform for its users' pages.
            if site == h or site in NEVER or subs.get(site, 0) < PLATFORM_MIN:
                continue
        out.add(h)
    return out


def hash64(host):
    return struct.unpack('>q', hashlib.sha256(host.encode('utf-8')).digest()[:8])[0]


def build(phishing, malware, date):
    p = sorted({hash64(h) for h in phishing})
    m = sorted({hash64(h) for h in malware})
    head = '\n'.join([
        HEADER,
        '# list-date: ' + date,
        '# phishing: %d' % len(p),
        '# malware: %d' % len(m),
        '', '',
    ]).encode('ascii')
    return head + struct.pack('>%dq' % len(p), *p) + struct.pack('>%dq' % len(m), *m)


def main(argv):
    if len(argv) != 6:
        sys.exit(__doc__)
    phishing_path, urlhaus_path, psl_path, top_path, out_path = argv[1:]
    psl = Suffixes(psl_path)
    top = read_top(top_path, TOP_SITES)
    phishing = keep(read_phishing(phishing_path), psl, top)
    malware = keep(read_hostfile(urlhaus_path), psl, top) - phishing
    if len(phishing) < 1000:
        sys.exit('Too few phishing hosts (%d): a source failed?' % len(phishing))
    date = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M')
    with open(out_path, 'wb') as f:
        f.write(build(phishing, malware, date))
    print('phishing %d, malware %d, top sites %d' % (len(phishing), len(malware), len(top)))


if __name__ == '__main__':
    main(sys.argv)
