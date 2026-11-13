#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Split the templates to build into independent groups for parallel jobs.

    ci/groups.py <template>...     -> JSON matrix on stdout

Templates that depend on each other (through hostmakedepends, makedepends,
depends or checkdepends, also via subpackages) end up in the same group, so
one job builds them in dependency order. Everything else runs in its own job.
Each group is emitted once per architecture it can be built for (archs=);
x86_64 and i686 are the only targets.

Output: {"include": [{"name": ..., "arch": ..., "pkgs": "a b c"}, ...]}
"""
import fnmatch
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "srcpkgs")
TARGETS = ("x86_64", "i686")
DEP_VARS = re.compile(r'(?:^|\s)(?:hostmakedepends|makedepends|depends|checkdepends)\+?="([^"]*)"', re.S)
ARCHS = re.compile(r'^archs="?([^"\n]*)"?', re.M)


def main_name(name):
    path = os.path.join(SRC, name)
    if os.path.islink(path):
        return os.path.basename(os.readlink(path))
    return name


def all_names():
    return {n: main_name(n) for n in os.listdir(SRC) if os.path.exists(os.path.join(SRC, n, "template"))}


def deps_of(main, names):
    text = open(os.path.join(SRC, main, "template")).read()
    found = set()
    for block in DEP_VARS.findall(text):
        for tok in re.split(r"[\s()'$]+", block):
            tok = re.split(r"[<>=]", tok, maxsplit=1)[0]
            if tok in names:
                found.add(names[tok])
    found.discard(main)
    return found


def archs_of(main):
    text = open(os.path.join(SRC, main, "template")).read()
    m = ARCHS.search(text)
    if not m:
        return list(TARGETS)
    pats = m.group(1).split()
    if "noarch" in pats:
        return ["x86_64"]
    out = []
    for t in TARGETS:
        allowed = any(fnmatch.fnmatch(t, p) for p in pats if not p.startswith("~"))
        denied = any(fnmatch.fnmatch(t, p[1:]) for p in pats if p.startswith("~"))
        only_neg = all(p.startswith("~") for p in pats)
        if (allowed or only_neg) and not denied:
            out.append(t)
    return out


def main():
    names = all_names()
    wanted = sorted({names[n] for n in sys.argv[1:] if n in names})
    parent = {p: p for p in wanted}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for p in wanted:
        for d in deps_of(p, names):
            if d in parent:
                parent[find(p)] = find(d)

    groups = {}
    for p in wanted:
        groups.setdefault(find(p), []).append(p)

    include = []
    for members in sorted(groups.values(), key=lambda m: (-len(m), m[0])):
        members.sort()
        name = members[0] if len(members) == 1 else f"{members[0]}+{len(members) - 1}"
        for arch in TARGETS:
            if any(arch in archs_of(m) for m in members):
                include.append({"name": name, "arch": arch, "pkgs": " ".join(members)})
    json.dump({"include": include}, sys.stdout)
    print()


if __name__ == "__main__":
    main()
