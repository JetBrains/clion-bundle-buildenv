#!/bin/bash
exec python3 "$(dirname "$0")/sync-mingw-packages.py" "$@"
