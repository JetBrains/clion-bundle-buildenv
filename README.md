[![team project](http://jb.gg/badges/team.svg)](https://github.com/JetBrains#jetbrains-on-github)
[![license](https://img.shields.io/badge/License-MIT-yellow.svg)](https://raw.githubusercontent.com/JetBrains/clion-bundle-buildenv/master/LICENSE)
# clion-bundle-buildenv

Dockerfiles, PKGBUILD scripts and makepkg configs for building GDB, LLDB, binutils and
GCC (the MinGW-w64 cross-toolchain) for Linux, MinGW-W64 and macOS (Darwin), from
source, reproducibly.

## Two entrypoints today

There are currently **two** build scripts in this repo, and neither is a drop-in
replacement for the other:

- **`build.sh`** — the entrypoint for **Linux** and **MinGW-W64**. Runs inside the
  Docker images built from `dockerfiles/`. Supports `-P/--pkgroot` (pick a package
  root independent of the config file), `--nomakepkg`/`--noinstall`/`--nobundle`,
  dependency-only builds, TeamCity parameter emission, etc.
- **`build2.sh`** — the entrypoint for **Darwin (macOS)**. Runs bare-metal on a Mac
  build agent (no Docker image for it). It's a smaller, independently-maintained
  script: it derives its package root from the directory of the `-c` config file
  (there is no `-P`/`--pkgroot` flag), and it doesn't support the
  `--nomakepkg`/`--noinstall`/`--nobundle`/`--nodeps`/`--onlydeps` partial-build
  options that `build.sh` has.

Unifying the two into a single entrypoint is a known follow-up (tracked separately)
but has **not** happened yet — treat them as two distinct, independently-runnable
build paths, each documented below.

## Building

### Linux (Docker)

Build the Docker image and run it with the repo root mounted as `/workdir`:
```
docker build -t clion-bundle-buildenv/linux:latest -f dockerfiles/linux.Dockerfile dockerfiles
docker run -v $(pwd):/workdir -it clion-bundle-buildenv/linux:latest
```

Inside the container, run `build.sh` against the Linux config:
```
./build.sh -P linux -c linux/makepkg.conf -- gdb
```
Substitute `lldb` for `gdb` to build LLDB instead (both live under `linux/`; LLDB is
**Linux-only** in this repo — there is no `mingw/lldb` package).

Artifacts appear in `artifacts-$CHOST/bundle.tar.xz` (e.g.
`artifacts-x86_64-redhat-linux/bundle.tar.xz`).

### MinGW-W64 (Docker)

Build the Docker image and run it the same way as Linux:
```
docker build -t clion-bundle-buildenv/mingw:latest -f dockerfiles/mingw.Dockerfile dockerfiles
docker run -v $(pwd):/workdir -it clion-bundle-buildenv/mingw:latest
```

Then run `build.sh` against one of the three MinGW arch configs:
```
./build.sh -P mingw -c mingw/makepkg-mingw64.conf -- gdb
```
- `mingw/makepkg-mingw64.conf` — `x86_64-w64-mingw32`
- `mingw/makepkg-mingw32.conf` — `i686-w64-mingw32`
- `mingw/makepkg-aarch64-w64-mingw32.conf` — `aarch64-w64-mingw32`

Only `gdb` is buildable here — again, there is **no `mingw/lldb`** package, so don't
pass `lldb` to a MinGW build.

See [mingw/README.md](mingw/README.md) for how individual MinGW packages are kept in
sync with upstream [MSYS2 MINGW-packages](https://github.com/msys2/MINGW-packages).

#### MinGW-W64 toolchain (binutils, make, GCC)

The cross-compilation toolchain itself (as opposed to GDB, which is *built with* the
toolchain) is built via its **own** config, using the `mingw-toolchain.Dockerfile`
image:
```
docker build -t clion-bundle-buildenv/mingw-toolchain:latest -f dockerfiles/mingw-toolchain.Dockerfile dockerfiles
docker run -v $(pwd):/workdir -it clion-bundle-buildenv/mingw-toolchain:latest
./build.sh -P mingw -c mingw/makepkg-mingw64-toolchain.conf -- binutils make gcc
```

`mingw/makepkg-mingw64-toolchain.conf` `source`s the regular
`mingw/makepkg-mingw64.conf` and adds two things on top: `KEEP_DEV_FILES=1` (keep
static/import libraries and headers that a bundled *toolchain* needs to link
anything at all, but a regular GDB build doesn't) and a `finalize_bundle()` hook that
pulls in a few makedepends-only packages and relocates `libgcc_s`.

**Do not fold this shaping into the shared `mingw/makepkg-mingw.conf.inc` or into
`mingw/makepkg-mingw64.conf`.** That is exactly what CPP-45129 did, and it broke
every *other* MinGW build that also sources `makepkg-mingw64.conf` (notably plain
GDB), forcing a revert. The toolchain-only conf exists specifically so this shaping
can never leak into `gdb`/`lldb` builds again — keep it in its own file.

For a local (non-CI) reproduction of the toolchain build, see
`scripts/build-mingw-toolchain-local.sh`.

### Darwin / macOS (bare metal, no Docker)

Darwin has no Docker image — `build2.sh` runs directly on a Mac. It needs:
- Bash >= 4.3 (macOS ships an ancient 3.2 as `/bin/bash`; use Homebrew's instead)
- The Homebrew tools listed at the top of `darwin/makepkg-darwin.conf.inc`:
  ```
  brew install bash coreutils git libarchive makepkg python3.12 m4 texinfo
  ```

Then, from the repo root:
```
/opt/homebrew/bin/bash ./build2.sh -c darwin/makepkg-x86_64.conf -- gdb
```
or, for Apple Silicon:
```
/opt/homebrew/bin/bash ./build2.sh -c darwin/makepkg-aarch64.conf -- gdb
```

Note `build2.sh` takes **no `-P`/`--pkgroot`** — it derives the package root from the
directory containing the `-c` config file (`darwin/`), so it must be pointed at one
of the `darwin/makepkg-*.conf` files directly. Only `gdb` is built for Darwin today.

Darwin's config layering: `darwin/makepkg-base.conf.inc` is the generic
pacman/makepkg defaults template (shared shape with the root `makepkg.conf.inc` used
by Linux/MinGW); `darwin/makepkg-darwin.conf.inc` layers the macOS/JetBrains-specific
overrides (Homebrew `PATH`, `clang`, code-signing/`install_name_tool` helpers, etc.)
and sources the base; the two entrypoints, `darwin/makepkg-aarch64.conf` and
`darwin/makepkg-x86_64.conf`, just set `CARCH` and source `makepkg-darwin.conf.inc`.

## Reproducibility

This repo's purpose is letting anyone rebuild the GDB/LLDB/binutils/GCC (GPL-licensed)
artifacts that ship in CLion, from source, without depending on JetBrains' internal CI.
Each platform section above is a complete, independently-runnable path: Linux and
MinGW-W64 need only Docker; Darwin needs only a Mac with the Homebrew tools listed
above. Neither path depends on TeamCity or any JetBrains-internal service — TeamCity
just automates running the same commands documented here.
