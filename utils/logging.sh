#!/bin/bash

# Centralized logging utility for claude-code-tools
# Usage: source this file and use log_message function

LOG_FILE="$CC_TOOLS_DIR/logs/cc-tools.log"
LOG_DIR="$CC_TOOLS_DIR/logs"

# Debug flag - can be set by environment variable or enable_debug function
CLAUDE_DEBUG="${CLAUDE_DEBUG:-false}"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Function to log messages with script name prefix
log_message() {
    local level="$1"
    local message="$2"
    local script_name="${3:-$(basename "${BASH_SOURCE[2]}")}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$script_name] [$level] $message" >> "$LOG_FILE"
    
    # Only output to stderr in debug mode to avoid duplicate logging
    if [[ "$CLAUDE_DEBUG" == "true" ]]; then
        echo "[$script_name] [$level] $message" >&2
    fi
}

# Convenience functions for different log levels
log_info() {
    log_message "INFO" "$1" "$2"
}

log_warn() {
    log_message "WARN" "$1" "$2"
}

log_error() {
    log_message "ERROR" "$1" "$2"
}

log_debug() {
    # Only log debug messages if debug mode is enabled
    if [[ "$CLAUDE_DEBUG" == "true" ]]; then
        log_message "DEBUG" "$1" "$2"
    fi
}

# Enable debug logging
enable_debug() {
    CLAUDE_DEBUG="true"
}

# Disable debug logging
disable_debug() {
    CLAUDE_DEBUG="false"
}

# Parse debug flag from arguments and remove it from the argument list
# Usage: parse_debug_flag "$@" 
# Sets CLAUDE_DEBUG=true if --debug is found and removes --debug from args
parse_debug_flag() {
    local new_args=()
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            enable_debug
        else
            new_args+=("$arg")
        fi
    done
    # Update the caller's argument array by printing the new args
    printf '%s\n' "${new_args[@]}"
}