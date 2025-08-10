#!/bin/bash

# Stop Script - Disables all features and stops background daemons

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$SCRIPT_DIR"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
PID_FILE_DIR="$CC_TOOLS_DIR/logs"
SMS_RECEIVER_PID_FILE="$PID_FILE_DIR/sms-receiver.pid"
RATE_LIMIT_MONITOR_PID_FILE="$PID_FILE_DIR/rate-limit-monitor.pid"

# Source logging utilities
source "$CC_TOOLS_DIR/utils/logging.sh"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log_info "$message"
}

# Disable features in config.json
print_color "$YELLOW" "Disabling all features in config.json..."
jq '.sms_enabled = false | .auto_resume = false' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
print_color "$RED" "✅ Features disabled."

# Stop SMS receiver daemon
if [ -f "$SMS_RECEIVER_PID_FILE" ]; then
    PID=$(cat "$SMS_RECEIVER_PID_FILE")
    print_color "$YELLOW" "Stopping SMS receiver daemon (PID: $PID)..."
    kill -9 $PID
    rm "$SMS_RECEIVER_PID_FILE"
    print_color "$RED" "✅ SMS receiver daemon stopped."
else
    print_color "$YELLOW" "SMS receiver daemon not running."
fi

# Stop rate limit monitor daemon
if [ -f "$RATE_LIMIT_MONITOR_PID_FILE" ]; then
    PID=$(cat "$RATE_LIMIT_MONITOR_PID_FILE")
    print_color "$YELLOW" "Stopping rate limit monitor daemon (PID: $PID)..."
    kill -9 $PID
    rm "$RATE_LIMIT_MONITOR_PID_FILE"
    print_color "$RED" "✅ Rate limit monitor daemon stopped."
else
    print_color "$YELLOW" "Rate limit monitor daemon not running."
fi

print_color "$RED" "All features have been stopped."