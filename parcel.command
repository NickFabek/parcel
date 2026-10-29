#!/bin/sh
# macOS launcher. The shared POSIX implementation lives beside this file.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$ROOT/parcel.sh" "$@"
