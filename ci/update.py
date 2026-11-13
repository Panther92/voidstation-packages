#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Find new upstream versions and fill in versions and checksums.

    ci/update.py [--pending] [pkg ...]

For every template with a srcpkgs/<pkg>/update.json (all, or the ones
named): ask upstream for the newest version; if it is newer than the
template's version (or the template is still a placeholder: version=0 or
checksum=PENDING), write the new version, reset revision=1, download the
distfiles and write their checksums.

--pending only handles placeholders (used on claude/** branches, so a new
template gets its first version without anyone downloading by hand).

Runs in CI (needs bash, git; xbps-uhelper for version comparison if
available). GITHUB_TOKEN is used for the GitHub API if set. distfiles are
expanded by sourcing the template in bash with the usual xbps-src helpers
stubbed out (x86_64, glibc).

update.json:
  {"source": "github-release", "repo": "owner/name",
   "tag": "^v(?P<version>[0-9.]+)$",            # optional, default below
   "asset": "name-{version}-x86_64.AppImage",   # optional: release must have it
   "prerelease": true,                          # optional: accept pre-releases
   "latest": true}                              # optional: only the release marked latest
  {"source": "github-tag", "repo": "owner/name", "tag": "..."}
  {"source": "json", "url": "...", "path": "key.sub.0.name", "regex": "..."}
  {"source": "text", "url": "...", "regex": "(?P<version>...)"}

Optional for every source:
  "replace": [["-", "."]]     applied to the version (xbps versions have no '-')
  "var": {"name": "_dl", "list": "assets.links", "pick": "x86_64.*AppImage$",
          "field": "direct_asset_url"}
                              json source only: write the download address of
                              the picked asset into the template variable
  "commit_var": "_commit"     github sources: write the commit the release tag
                              points to into this variable (for templates that
                              fetch with git in do_fetch, e.g. because of
                              submodules; they have no distfiles/checksum)

Prints the names of the changed templates, one per line, on stdout.
"""
import json
import os
import re
import hashlib
import shutil
import subprocess
import sys
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "srcpkgs")
DEFAULT_TAG = r"^v?(?P<version>\d+(?:\.\d+)*)$"
VERSION_OK = re.compile(r"^[0-9][0-9A-Za-z._+]*$")      # xbps: no '-' in versions
UA = {"User-Agent": "voidstation-packages update check"}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def http(url, accept=None):
    headers = dict(UA)
    if accept:
        headers["Accept"] = accept
    if url.startswith("https://api.github.com/") and os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def match_version(rx, text):
    m = re.search(rx, text)
    if not m:
        return None
    return m.groupdict().get("version") or (m.group(1) if m.groups() else m.group(0))


def vkey(v):
    return [int(p) if p.isdigit() else p for p in re.split(r"[._+]", v)]


EXTRA_VARS = {}


def dig(doc, path):
    for part in (path or "").split("."):
        if part == "":
            continue
        doc = doc[int(part)] if isinstance(doc, list) else doc[part]
    return doc


def tag_commit(repo, tag):
    """Commit a tag points to (peeled for annotated tags)."""
    out = subprocess.run(["git", "ls-remote", f"https://github.com/{repo}", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"],
                         capture_output=True, text=True, check=True).stdout.split("\n")
    refs = dict(reversed(line.split("\t", 1)) for line in out if "\t" in line)
    sha = refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}")
    if not sha:
        raise ValueError(f"tag {tag} not found in {repo}")
    return sha


def resolve(cfg):
    src = cfg["source"]
    if src == "github-release":
        rx = cfg.get("tag", DEFAULT_TAG)
        if cfg.get("latest"):
            # the release GitHub marks as latest; for repos whose newest 50
            # releases are all nightlies (PCSX2)
            rels = [json.loads(http(f"https://api.github.com/repos/{cfg['repo']}/releases/latest",
                                    "application/vnd.github+json"))]
        else:
            rels = json.loads(http(f"https://api.github.com/repos/{cfg['repo']}/releases?per_page=50",
                                   "application/vnd.github+json"))
        found = []
        for rel in rels:
            if rel.get("draft") or (rel.get("prerelease") and not cfg.get("prerelease")):
                continue
            v = match_version(rx, rel.get("tag_name") or "")
            if not v:
                continue
            if cfg.get("asset"):
                want = cfg["asset"].format(version=v, tag=rel["tag_name"])
                if want not in {a.get("name") for a in rel.get("assets") or []}:
                    continue
            found.append(v)
        return max(found, key=vkey) if found else None
    if src == "github-tag":
        rx = cfg.get("tag", DEFAULT_TAG)
        out = subprocess.run(["git", "ls-remote", "--tags", "--refs", f"https://github.com/{cfg['repo']}"],
                             capture_output=True, text=True, check=True).stdout
        found = [v for v in (match_version(rx, line.split("refs/tags/", 1)[-1]) for line in out.splitlines()) if v]
        return max(found, key=vkey) if found else None
    if src == "json":
        doc = json.loads(http(cfg["url"]))
        v = match_version(cfg.get("regex", r"(?P<version>\d[\w.-]*)"), str(dig(doc, cfg.get("path", ""))))
        if v and cfg.get("var"):
            spec = cfg["var"]
            pick = re.compile(spec["pick"])
            hits = [a for a in dig(doc, spec["list"]) if pick.search(str(a.get("name", "")) + " " + str(a.get(spec["field"], "")))]
            if not hits:
                raise ValueError(f"no asset matches {spec['pick']}")
            EXTRA_VARS[spec["name"]] = hits[0][spec["field"]]
        return v
    if src == "text":
        return match_version(cfg["regex"], http(cfg["url"]))
    raise ValueError(f"unknown source {src}")


def cmpver(a, b):
    """1 if a > b, 0 if equal, -1 if a < b (xbps rules if available)."""
    if shutil.which("xbps-uhelper"):
        rc = subprocess.run(["xbps-uhelper", "cmpver", a, b]).returncode
        return {0: 0, 1: 1, 255: -1}.get(rc, -1)
    return (vkey(a) > vkey(b)) - (vkey(a) < vkey(b))


EXPAND = r"""
set +eu
vopt_if() { :; }; vopt_bool() { :; }; vopt_with() { :; }; vopt_enable() { :; }; vopt_conflict() { :; }
XBPS_TARGET_MACHINE=x86_64 XBPS_MACHINE=x86_64 XBPS_TARGET_LIBC=glibc XBPS_TARGET_WORDSIZE=64
. "$1" >/dev/null 2>&1
for f in $distfiles; do printf '%s\n' "$f"; done
"""


def distfiles(tpl):
    out = subprocess.run(["bash", "-c", EXPAND, "expand", tpl], capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if line.strip()]


def sha256_url(url):
    req = urllib.request.Request(url, headers=UA)
    h = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=600) as r:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def set_checksums(text, sums):
    value = sums[0] if len(sums) == 1 else '"' + "\n ".join(sums) + '"'
    # replace a single-line or a quoted multi-line assignment
    new, n = re.subn(r'^checksum=(?:"[^"]*"|\S*)$', lambda m: "checksum=" + value, text, count=1, flags=re.M)
    if n == 0:
        raise ValueError("no checksum= line in the template")
    return new


def get_var(text, name):
    m = re.search(rf"^{name}=\"?([^\"\n]*)\"?$", text, re.M)
    return m.group(1) if m else None


def set_var(text, name, value):
    return re.sub(rf"^{name}=.*$", f"{name}={value}", text, count=1, flags=re.M)


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    pending_only = "--pending" in args
    names = [a for a in args if not a.startswith("--")]
    if not names:
        names = sorted(n for n in os.listdir(SRC) if os.path.isfile(os.path.join(SRC, n, "update.json")))
    changed, failed = [], []
    for pkg in names:
        tpl = os.path.join(SRC, pkg, "template")
        cfg_path = os.path.join(SRC, pkg, "update.json")
        if not os.path.isfile(cfg_path):
            continue
        text = open(tpl).read()
        cur = get_var(text, "version") or "0"
        placeholder = cur == "0" or get_var(text, "checksum") == "PENDING"
        if pending_only and not placeholder:
            continue
        EXTRA_VARS.clear()
        try:
            cfg = json.load(open(cfg_path))
            latest = resolve(cfg)
            for a, b in cfg.get("replace", []):
                latest = latest.replace(a, b) if latest else latest
        except Exception as e:  # noqa: BLE001 - report and go on with the next template
            log(f"::warning title={pkg}::update check failed: {e}")
            failed.append(pkg)
            continue
        if not latest or not VERSION_OK.match(latest):
            log(f"::warning title={pkg}::no usable upstream version ({latest!r})")
            failed.append(pkg)
            continue
        newer = cur == "0" or cmpver(latest, cur) > 0
        if not newer and not placeholder:
            log(f"{pkg}: {cur} is current")
            continue
        if newer and cfg.get("commit_var"):
            tag = cfg.get("tag_format", "v{version}").format(version=latest)
            EXTRA_VARS[cfg["commit_var"]] = tag_commit(cfg["repo"], tag)
        if newer:
            text = set_var(text, "version", latest)
            text = set_var(text, "revision", "1")
            for name, value in EXTRA_VARS.items():
                text = set_var(text, name, f'"{value}"')
        open(tpl, "w").write(text)
        try:
            files = distfiles(tpl)
            if not files and cfg.get("commit_var"):
                log(f"{pkg}: {cur} -> {latest} (git, commit {EXTRA_VARS.get(cfg['commit_var'], '?')[:12]})")
                changed.append(pkg)
                continue
            if not files:
                raise ValueError("distfiles is empty")
            sums = [sha256_url(f.split(">", 1)[0]) for f in files]
            text = set_checksums(text, sums)
        except Exception as e:  # noqa: BLE001
            log(f"::warning title={pkg}::checksums failed: {e}")
            subprocess.run(["git", "checkout", "--", tpl], cwd=ROOT)
            failed.append(pkg)
            continue
        open(tpl, "w").write(text)
        log(f"{pkg}: {cur} -> {get_var(open(tpl).read(), 'version')}")
        changed.append(pkg)
    for pkg in changed:
        print(pkg)
    if failed:
        log("update check failed for: " + " ".join(failed))


if __name__ == "__main__":
    main()
