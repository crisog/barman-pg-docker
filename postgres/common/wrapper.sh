#!/bin/bash
set -e

# Force the built-in Docker entrypoint to use a local UNIX socket
unset PGHOST
unset PGPORT

exec /usr/local/bin/docker-entrypoint.sh "$@"
