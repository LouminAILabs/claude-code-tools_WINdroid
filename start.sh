#!/bin/bash

# Start Script - Enables all features and starts background daemons

# Parse debug flag
DEBUG_FLAG=""
if [[ "$1" == "--debug" ]]; then
    export CLAUDE_DEBUG="true"
    DEBUG_FLAG="--debug"
    shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$SCRIPT_DIR"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
PID_FILE_DIR="$CC_TOOLS_DIR/logs"
SMS_RECEIVER_PID_FILE="$PID_FILE_DIR/sms-receiver.pid"
RATE_LIMIT_MONITOR_PID_FILE="$PID_FILE_DIR/rate-limit-monitor.pid"

# Source logging utilities
source "$CC_TOOLS_DIR/utils/logging.sh"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log_info "$message"
}

# Create PID directory if it doesn't exist
mkdir -p "$PID_FILE_DIR"

log_info "Starting claude-code-tools initialization"

# Enable features in config.json
print_color "$YELLOW" "Enabling all features in config.json..."
jq '.sms_enabled = true | .auto_resume = true' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
print_color "$GREEN" "✅ Features enabled."

# Function to list windows for a terminal app and get process ID
list_terminal_windows() {
    local app="$1"
    case "$app" in
        "Terminal")
            osascript <<EOF
tell application "Terminal"
    set windowList to {}
    repeat with i from 1 to count of windows
        set windowInfo to "Window " & i & ": " & (name of window i)
        set end of windowList to windowInfo
    end repeat
    return my list_to_string(windowList, "\n")
end tell

on list_to_string(lst, delimiter)
    set AppleScript's text item delimiters to delimiter
    set string_result to lst as string
    set AppleScript's text item delimiters to ""
    return string_result
end list_to_string
EOF
            ;;
        "iTerm"|"iTerm2")
            osascript <<EOF
tell application "$app"
    set windowList to {}
    repeat with w from 1 to count of windows
        repeat with t from 1 to count of tabs of window w
            repeat with s from 1 to count of sessions of tab t of window w
                try
                    set sessionInfo to "Window " & w & " Tab " & t & " Session " & s & ": " & (name of session s of tab t of window w)
                on error
                    set sessionInfo to "Window " & w & " Tab " & t & " Session " & s & ": (Unnamed session)"
                end try
                set end of windowList to sessionInfo
            end repeat
        end repeat
    end repeat
    return my list_to_string(windowList, "\n")
end tell

on list_to_string(lst, delimiter)
    set AppleScript's text item delimiters to delimiter
    set string_result to lst as string
    set AppleScript's text item delimiters to ""
    return string_result
end list_to_string
EOF
            ;;
    esac
}

# Function to get process ID for selected window
get_window_process_id() {
    local app="$1"
    local selection="$2"
    case "$app" in
        "Terminal")
            # Parse window number from selection string like "Window 1: Terminal - title"
            local window_num=$(echo "$selection" | sed -n 's/Window \([0-9]*\):.*/\1/p')
            osascript <<EOF
tell application "Terminal"
    return id of window $window_num
end tell
EOF
            ;;
        "iTerm"|"iTerm2")
            # Parse window, tab, and session numbers from selection
            local window_num=$(echo "$selection" | sed -n 's/Window \([0-9]*\) Tab.*/\1/p')
            local tab_num=$(echo "$selection" | sed -n 's/Window [0-9]* Tab \([0-9]*\) Session.*/\1/p')
            local session_num=$(echo "$selection" | sed -n 's/Window [0-9]* Tab [0-9]* Session \([0-9]*\).*/\1/p')
            # Return window:tab:session format instead of session ID (which is ephemeral)
            echo "${window_num}:${tab_num}:${session_num}"
            ;;
    esac
}

# Always prompt user to select terminal configuration
print_color "$YELLOW" "Please select your Claude Code terminal configuration."

# Terminal app selection
echo "Which terminal app do you use for Claude Code?"
echo "1) Terminal"
echo "2) iTerm"
echo "3) iTerm2"
read -p "Enter your choice (1-3): " choice

case "$choice" in
    1) terminal_app="Terminal" ;;
    2) terminal_app="iTerm" ;;
    3) terminal_app="iTerm2" ;;
    *) echo "Invalid choice. Defaulting to Terminal."; terminal_app="Terminal" ;;
esac

print_color "$YELLOW" "Listing available windows for $terminal_app..."

# Get list of windows
windows=$(list_terminal_windows "$terminal_app")
if [ -z "$windows" ]; then
    echo "No windows found for $terminal_app. Please make sure the application is running with at least one window."
    exit 1
fi

echo "Available windows:"
echo "$windows" | nl -w2 -s") "

read -p "Select the window number for Claude Code: " window_choice

# Get the selected window info
selected_window=$(echo "$windows" | sed -n "${window_choice}p")
if [ -z "$selected_window" ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

# Get process ID for the selected window
process_id=$(get_window_process_id "$terminal_app" "$selected_window")

# Save configuration
jq --arg app "$terminal_app" --arg pid "$process_id" '.terminal_app = $app | .claude_terminal_process_id = $pid | del(.claude_terminal_identifier)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

log_info "Terminal configuration saved: App=$terminal_app, Process ID=$process_id"
print_color "$GREEN" "✅ Terminal configuration saved (App: $terminal_app, Process ID: $process_id)."

# Make send-to-claude.sh executable
if [ -f "$CC_TOOLS_DIR/utils/send-to-claude.sh" ]; then
    chmod +x "$CC_TOOLS_DIR/utils/send-to-claude.sh"
fi

# Start SMS receiver daemon
if [ -f "$SMS_RECEIVER_PID_FILE" ] && ps -p $(cat "$SMS_RECEIVER_PID_FILE") > /dev/null; then
    print_color "$GREEN" "✅ SMS receiver daemon is already running with PID $(cat $SMS_RECEIVER_PID_FILE)."
else
    print_color "$YELLOW" "Starting SMS receiver daemon..."
    nohup "$CC_TOOLS_DIR/sms/sms-receiver.sh" $DEBUG_FLAG --daemon > "$CC_TOOLS_DIR/logs/sms-receiver.log" 2>&1 &
    echo $! > "$SMS_RECEIVER_PID_FILE"
    print_color "$GREEN" "✅ SMS receiver daemon started with PID $(cat $SMS_RECEIVER_PID_FILE)."
fi

# Start rate limit monitor daemon
if [ -f "$RATE_LIMIT_MONITOR_PID_FILE" ] && ps -p $(cat "$RATE_LIMIT_MONITOR_PID_FILE") > /dev/null; then
    print_color "$GREEN" "✅ Rate limit monitor daemon is already running with PID $(cat $RATE_LIMIT_MONITOR_PID_FILE)."
else
    print_color "$YELLOW" "Starting rate limit monitor daemon..."
    nohup "$CC_TOOLS_DIR/auto_resume/rate-limit-monitor.sh" $DEBUG_FLAG --daemon > "$CC_TOOLS_DIR/logs/rate-limit-monitor.log" 2>&1 &
    echo $! > "$RATE_LIMIT_MONITOR_PID_FILE"
    print_color "$GREEN" "✅ Rate limit monitor daemon started with PID $(cat $RATE_LIMIT_MONITOR_PID_FILE)."
fi

log_info "All features have been started successfully"
print_color "$GREEN" "All features have been started."

# tail -f "$CC_TOOLS_DIR/logs/cc-tools.log"