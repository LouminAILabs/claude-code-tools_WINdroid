#!/bin/bash

# Sends a command to the Claude Code terminal window.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
COMMAND_TO_SEND="$1"

if [ -z "$COMMAND_TO_SEND" ]; then
    echo "Usage: $0 \"<command>\"" >&2
    exit 1
fi

# Function to escape a string for use in an AppleScript string literal.
escape_for_applescript() {
    echo -n "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

ESCAPED_COMMAND=$(escape_for_applescript "$COMMAND_TO_SEND")

# Read terminal info from config
TERMINAL_APP=$(jq -r '.terminal_app // "Terminal"' "$CONFIG_FILE")
CLAUDE_PROCESS_ID=$(jq -r '.claude_terminal_process_id // empty' "$CONFIG_FILE")

if [ -z "$CLAUDE_PROCESS_ID" ]; then
    echo "Error: Claude Code terminal process ID not set in config.json." >&2
    echo "Please run start.sh to configure it." >&2
    exit 1
fi

chmod +x "$0"

if [ "$TERMINAL_APP" = "Terminal" ]; then
    # NOTE: Terminal.app's AppleScript API does not support writing characters
    # to a session directly without using System Events.
    # As per the request to avoid System Events, this will now execute the command
    # directly, without the preceding Escape and 'i' keystrokes.
    osascript <<EOF
    tell application "Terminal"
        activate
        try
            set claudeWindow to first window whose id is $CLAUDE_PROCESS_ID
            do script "$ESCAPED_COMMAND" in claudeWindow
            do script "" in claudeWindow
        on error
            display dialog "Could not find the configured Terminal window (ID: $CLAUDE_PROCESS_ID), or error sending command to Terminal window. Try to re-run start.sh to choose the terminal window."
        end try
    end tell
EOF
elif [ "$TERMINAL_APP" = "iTerm" ] || [ "$TERMINAL_APP" = "iTerm2" ]; then
    IFS=':' read -r window_num tab_num session_num <<< "$CLAUDE_PROCESS_ID"
    osascript <<EOF
    tell application "$TERMINAL_APP"
        activate
        try
            # Explicitly select the window and tab to ensure it is in the foreground
            select window $window_num
            select tab $tab_num of window $window_num

            set target_session to session $session_num of tab $tab_num of window $window_num
            tell target_session
                # This only works in normal edit mode, or INSERT mode in vim edit mode. 
                write text "$ESCAPED_COMMAND" without newline
                # Send Enter keystroke
                write text ""
            end tell
        on error
            display dialog "Could not find the configured iTerm session (Window: $window_num, Tab: $tab_num, Session: $session_num), or error sending command to the session. Try to re-run start.sh to choose the session. "
        end try
    end tell
EOF
else
    echo "Unsupported terminal app: $TERMINAL_APP" >&2
    exit 1
fi
