#!/bin/bash
# Install the optional GAT Auto-ID model alongside MoE detection.
exec /bin/bash "$(dirname -- "$0")/Setup-Mac.command" --with-gat "$@"
