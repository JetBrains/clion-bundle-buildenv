#!/usr/bin/env python3
"""Sync MinGW package PKGBUILDs from upstream MSYS2 MINGW-packages.

For each package with an upstream.conf, fetches the upstream PKGBUILD,
extracts version/source/patch info, downloads patches, and renders
the cross-compile PKGBUILD from the local template.

Usage:
    sync-mingw-packages.sh [--all | PACKAGE ...]

Examples:
    sync-mingw-packages.sh gcc             # sync just gcc
    sync-mingw-packages.sh headers crt     # sync headers and crt
    sync-mingw-packages.sh --all           # sync all packages with upstream.conf
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

GITHUB_RAW = "https://raw.githubusercontent.com/msys2/MINGW-packages"
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
MINGW_DIR = REPO_ROOT / "mingw"
PARSE_HELPER = SCRIPT_DIR / "parse-pkgbuild.sh"

GENERATED_HEADER = (
    "# Do not edit PKGBUILD directly — it is generated from PKGBUILD.template by\n"
    "# scripts/sync-mingw-packages.sh using upstream.conf. Edit the template or conf instead.\n"
)


# ── Data types ───────────────────────────────────────────────────────

@dataclass
class Patch:
    name: str
    checksum: str


@dataclass
class UpstreamData:
    pkgver: str
    source_url: str = ""
    source_checksum: str = "SKIP"
    patches: list[Patch] = field(default_factory=list)


# ── Upstream config ──────────────────────────────────────────────────

def read_upstream_conf(path: Path) -> tuple[str, str]:
    conf: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            conf[k.strip()] = v.strip()
    commit = conf.get("UPSTREAM_COMMIT", "")
    pkg_path = conf.get("UPSTREAM_PACKAGE_PATH", "")
    if not commit:
        raise ValueError(f"UPSTREAM_COMMIT not set in {path}")
    if not pkg_path:
        raise ValueError(f"UPSTREAM_PACKAGE_PATH not set in {path}")
    return commit, pkg_path


# ── Fetch & parse ────────────────────────────────────────────────────

def fetch(url: str) -> bytes:
    try:
        with urlopen(url, timeout=30) as resp:
            return resp.read()
    except URLError as e:
        raise RuntimeError(f"Failed to fetch {url}: {e}") from e


def parse_pkgbuild(pkgbuild_path: Path) -> dict:
    result = subprocess.run(
        [str(PARSE_HELPER), str(pkgbuild_path)],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to parse {pkgbuild_path}: {result.stderr}")

    data: dict = {"source": [], "sha256sums": []}
    for line in result.stdout.splitlines():
        tag, _, value = line.partition("\t")
        if tag == "PKGVER":
            data["pkgver"] = value
        elif tag == "SOURCE":
            data["source"].append(value)
        elif tag == "SHA256":
            data["sha256sums"].append(value)
    if "pkgver" not in data:
        raise RuntimeError(f"No PKGVER found in {pkgbuild_path}")
    return data


def classify_sources(raw: dict) -> UpstreamData:
    data = UpstreamData(pkgver=raw["pkgver"])

    for i, (src, cksum) in enumerate(zip(raw["source"], raw["sha256sums"])):
        basename = src.rsplit("/", 1)[-1] if "/" in src else src

        if not data.source_url and (i == 0 or not basename.endswith((".patch", ".sig"))):
            data.source_url = src
            data.source_checksum = cksum
            continue

        if basename.endswith(".sig") or cksum == "SKIP":
            continue
        if not basename.endswith(".patch"):
            continue

        data.patches.append(Patch(basename, cksum))

    # SourceForge git is unreliable on CI; prefer GitHub mirror
    data.source_url = data.source_url.replace(
        "git+https://git.code.sf.net/p/mingw-w64/mingw-w64",
        "git+https://github.com/mingw-w64/mingw-w64.git",
    )

    # makepkg 5.0.2 cannot checksum git sources
    if "::git+" in data.source_url:
        data.source_checksum = "SKIP"

    return data


# ── Download patches ─────────────────────────────────────────────────

def download_patches(data: UpstreamData, pkg_dir: Path, commit: str, pkg_path: str):
    for patch in data.patches:
        url = f"{GITHUB_RAW}/{commit}/{pkg_path}/{patch.name}"
        print(f"  downloading: {patch.name}")
        content = fetch(url)
        (pkg_dir / patch.name).write_bytes(content)


# ── Template rendering ───────────────────────────────────────────────

def render_template(template_path: Path, data: UpstreamData) -> str:
    template = template_path.read_text()

    template = template.replace("{{PKGVER}}", data.pkgver)
    template = template.replace("{{SOURCE_URL}}", data.source_url)
    template = template.replace("{{SOURCE_CHECKSUM}}", data.source_checksum)

    if data.patches:
        template = template.replace("{{PATCH_LIST}}", "\n  ".join(p.name for p in data.patches))
        template = template.replace("{{CHECKSUMS}}", "\n  ".join(p.checksum for p in data.patches))
    else:
        template = template.replace("{{PATCH_LIST}}", "")
        template = template.replace("{{CHECKSUMS}}", "")

    return GENERATED_HEADER + template


# ── Sync one package ─────────────────────────────────────────────────

def sync_package(pkg_dir: Path):
    pkg_name = pkg_dir.name

    upstream_conf = pkg_dir / "upstream.conf"
    if not upstream_conf.exists():
        print(f"skip: {pkg_name} (no upstream.conf)")
        return

    template_path = pkg_dir / "PKGBUILD.template"
    if not template_path.exists():
        print(f"skip: {pkg_name} (no PKGBUILD.template)")
        return

    commit, pkg_path = read_upstream_conf(upstream_conf)
    print(f"==> Syncing {pkg_name} from {pkg_path}@{commit[:12]}...")

    # Fetch and parse upstream PKGBUILD
    url = f"{GITHUB_RAW}/{commit}/{pkg_path}/PKGBUILD"
    with tempfile.NamedTemporaryFile(mode="wb", suffix=".PKGBUILD", delete=True) as tmp:
        tmp.write(fetch(url))
        tmp.flush()
        raw = parse_pkgbuild(Path(tmp.name))

    data = classify_sources(raw)
    print(f"  version: {data.pkgver}")
    print(f"  patches: {len(data.patches)}")

    download_patches(data, pkg_dir, commit, pkg_path)

    pkgbuild = render_template(template_path, data)
    (pkg_dir / "PKGBUILD").write_text(pkgbuild)
    print(f"  generated: {pkg_dir / 'PKGBUILD'}")


# ── CLI ──────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} [--all | PACKAGE ...]", file=sys.stderr)
        sys.exit(1)

    if sys.argv[1] == "--all":
        pkg_dirs = sorted(p.parent for p in MINGW_DIR.glob("*/upstream.conf"))
    else:
        pkg_dirs = []
        for name in sys.argv[1:]:
            pkg_dir = MINGW_DIR / name
            if not pkg_dir.is_dir():
                print(f"error: package directory not found: {pkg_dir}", file=sys.stderr)
                sys.exit(1)
            pkg_dirs.append(pkg_dir)

    for pkg_dir in pkg_dirs:
        sync_package(pkg_dir)

    print("Done.")


if __name__ == "__main__":
    main()
