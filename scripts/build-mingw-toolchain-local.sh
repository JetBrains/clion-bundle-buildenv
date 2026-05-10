#!/bin/bash
# Local Docker-based build for MinGW-w64 toolchain
# Replicates TC build configuration: ijplatform_master_CIDR_ExternalTools_MingwToolchain
# Usage:
#   ./scripts/build-local.sh                    # build: binutils make gcc (default)
#   ./scripts/build-local.sh gcc                # rebuild only gcc
#   ./scripts/build-local.sh --rebuild-image    # force-rebuild Docker image first
#   ./scripts/build-local.sh --shell            # drop into container shell for debugging

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_IMAGE="mingw-toolchain-local:latest"
PACKAGES="${1:-binutils make gcc}"
REBUILD_IMAGE=false

# Parse flags
case "${1:-}" in
  --rebuild-image)
    REBUILD_IMAGE=true
    PACKAGES="binutils make gcc"
    ;;
  --shell)
    PACKAGES=""
    ;;
  -*)
    echo "Usage: $0 [PACKAGES] | [--rebuild-image] | [--shell]" >&2
    exit 1
    ;;
esac

# Ensure Docker daemon is running
if ! docker ps >/dev/null 2>&1; then
  echo "Error: Docker daemon not running. Start Docker Desktop or colima first." >&2
  exit 1
fi

# Build the Docker image if needed
if [ "$REBUILD_IMAGE" = true ] || ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
  echo "Building Docker image: $DOCKER_IMAGE"
  docker build --platform linux/amd64 \
    -f "$REPO_ROOT/dockerfiles/mingw-toolchain.Dockerfile" \
    -t "$DOCKER_IMAGE" "$REPO_ROOT/dockerfiles"
fi

# Prepare environment
export DESTDIR="artifacts-mingw"
export BUILD_NUMBER="${BUILD_NUMBER:-local-$(date +%s)}"
export TEAMCITY_VERSION="${TEAMCITY_VERSION:-}"
export TEAMCITY_PARAMETER_PREFIX="clion."

# Reuse or create a named Docker volume for artifacts (avoids fakeroot permission issues on bind mounts).
# Set REUSE_VOLUME=<name> to keep the cached makepkg build dir from a prior run
# (lets you re-iterate on a single failing package without rebuilding the
# upstream chain). Default: fresh volume per run.
VOLUME_NAME="${REUSE_VOLUME:-mingw-build-v$(date +%s)}"
KEEP_VOLUME="${KEEP_VOLUME:-${REUSE_VOLUME:+1}}"
if [ "$(uname)" = "Darwin" ]; then
  if [ -n "${REUSE_VOLUME:-}" ] && docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo "Reusing Docker volume: $VOLUME_NAME"
  else
    echo "Creating Docker volume for build artifacts: $VOLUME_NAME"
    docker volume create "$VOLUME_NAME" >/dev/null
  fi
fi

# Stage repo into a tmp dir, dropping .git so the worktree's broken .git
# pointer doesn't leak into the container. Without this, build.sh's
# `git config user.name` follows /workdir/.git -> a host path the container
# can't see and fatals "not a git repository". Tar-pipe is fast (<1 MB).
#
# IMPORTANT on macOS+colima: stage under $HOME, not /var/folders. colima
# only auto-mounts $HOME into the VM; /var/folders is invisible to the
# container, so a bind mount of a /tmp staging dir would appear empty.
STAGE_PARENT="${TMPDIR_LOCAL:-$HOME/.cache/mingw-build-local}"
mkdir -p "$STAGE_PARENT"
STAGE_DIR="$(mktemp -d "$STAGE_PARENT/stage-XXXXXX")"
trap 'rm -rf "$STAGE_DIR" 2>/dev/null || true' EXIT
echo "Staging repo into $STAGE_DIR (excluding .git, .idea, artifacts)"
tar -C "$REPO_ROOT" \
    --exclude='./.git' \
    --exclude='./.idea' \
    --exclude='./artifacts-mingw' \
    --exclude='./artifacts' \
    -cf - . | tar -C "$STAGE_DIR" -xf -

# Build the run command with mounts and env
# Key differences from TC:
#   - No -u $(id -u) (Docker Desktop/colima handle UID mapping; container runs as 'build' user)
#   - No /etc/passwd mount (breaks build user environment)
#   - No $HOME mount: we stage the repo without .git so makepkg never needs
#     to dereference the host worktree pointer; git committer identity is
#     supplied via env vars below.
#   - On macOS: use Docker volume for artifacts (avoids fakeroot + virtiofs issues)
#   - On Linux: use bind mount

docker_run_args=(
  --rm
  -e "BUILD_NUMBER=$BUILD_NUMBER"
  -e "TEAMCITY_VERSION=${TEAMCITY_VERSION:-}"
  -e "TEAMCITY_PARAMETER_PREFIX=$TEAMCITY_PARAMETER_PREFIX"
  -e "DESTDIR=$DESTDIR"
  -e "GIT_COMMITTER_NAME=local-build"
  -e "GIT_COMMITTER_EMAIL=local-build@example.invalid"
  -e "GIT_AUTHOR_NAME=local-build"
  -e "GIT_AUTHOR_EMAIL=local-build@example.invalid"
)

# Forward proxy settings if set (for corporate networks)
if [ -n "${HTTP_PROXY:-}" ]; then
  docker_run_args+=(-e "HTTP_PROXY=$HTTP_PROXY")
fi
if [ -n "${HTTPS_PROXY:-}" ]; then
  docker_run_args+=(-e "HTTPS_PROXY=$HTTPS_PROXY")
fi
if [ -n "${NO_PROXY:-}" ]; then
  docker_run_args+=(-e "NO_PROXY=$NO_PROXY")
fi

# Workdir mount: staged repo (no .git) at /workdir (TC convention).
# On macOS: also use Docker volume for artifacts to work around fakeroot + virtiofs issues.
docker_run_args+=(-v "$STAGE_DIR:/workdir")
if [ "$(uname)" = "Darwin" ]; then
  docker_run_args+=(-v "$VOLUME_NAME:/artifact-build")
fi

# Run the build or shell
if [ -z "$PACKAGES" ]; then
  # --shell: drop into bash
  echo "Dropping into container shell. Run './build.sh --help' to verify build script is available."
  docker run "${docker_run_args[@]}" "$DOCKER_IMAGE" /bin/bash
else
  # Build: run build.sh with specified packages
  echo "Building packages: $PACKAGES"
  docker run "${docker_run_args[@]}" "$DOCKER_IMAGE" \
    bash -exu -c "
      unset TMP TMPDIR TEMP
      # Keep LANG=C.UTF-8 from the Dockerfile so bsdtar can extract tarballs
      # with non-ASCII pathnames (gcc-15.2.0.tar.xz contains po/ entries that
      # require UTF-8). Plain C locale fails with 'Pathname can't be converted'.
      export BUILD_NUMBER TEAMCITY_VERSION TEAMCITY_PARAMETER_PREFIX DESTDIR
      cd /workdir
      # On macOS: override DESTDIR to use Docker volume (avoids fakeroot permission issues)
      if [ -d /artifact-build ]; then
        # Ensure volume is writable by build user
        sudo chown build:build /artifact-build
        export DESTDIR=/artifact-build/artifacts-mingw
        mkdir -p \$DESTDIR
      fi
      ./build.sh -P 'mingw' -c 'mingw/makepkg-mingw64.conf' -- $PACKAGES
    "

  # On macOS: copy artifacts from Docker volume back to host
  if [ "$(uname)" = "Darwin" ]; then
    echo "Copying artifacts from Docker volume back to host..."
    docker run --rm \
      -v "$VOLUME_NAME:/artifact-build" \
      -v "$REPO_ROOT:/workdir" \
      ubuntu:24.04 \
      bash -c "cp -r /artifact-build/artifacts-mingw /workdir/ && echo 'Artifacts copied'"
    # Clean up the volume unless caller wants to re-iterate
    if [ -z "${KEEP_VOLUME:-}" ]; then
      docker volume rm "$VOLUME_NAME" >/dev/null || true
    else
      echo "Keeping volume $VOLUME_NAME for next run (REUSE_VOLUME=$VOLUME_NAME)"
    fi
  fi
fi

echo "Build complete. Artifacts in: $REPO_ROOT/$DESTDIR"
