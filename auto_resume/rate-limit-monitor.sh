#!/bin/bash

# Rate Limit Monitor - Periodically checks for a rate-limited state and resumes when expired.
# Usage: rate-limit-monitor.sh [--debug] [--daemon]

# Parse debug flag before sourcing logging utilities
if [[ "$1" == "--debug" ]]; then
    export CLAUDE_DEBUG="true"
    shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
RATE_LIMITED_STATE_FILE="$CC_TOOLS_DIR/logs/rate-limited-state.json"

# Source centralized logging utilities
source "$CC_TOOLS_DIR/utils/logging.sh"

# Function to check if it's time to resume
check_resume_time() {
    if [ ! -f "$RATE_LIMITED_STATE_FILE" ]; then
        return 1
    fi
    
    local expires_at=$(jq -r '.expires_at // 0' "$RATE_LIMITED_STATE_FILE" 2>/dev/null)
    if [ "$expires_at" -eq 0 ]; then
        log_warn "Invalid expires_at value in rate-limited-state.json"
        rm -f "$RATE_LIMITED_STATE_FILE"
        return 1
    fi
    
    local current_timestamp=$(date +%s)
    # Add 60 seconds (1 minute) buffer after the reset time
    local resume_timestamp=$((expires_at + 60))
    
    if [ "$current_timestamp" -ge "$resume_timestamp" ]; then
        local expires_at_readable=$(date -r "$expires_at" "+%Y-%m-%d %H:%M:%S")
        local resume_at_readable=$(date -r "$resume_timestamp" "+%Y-%m-%d %H:%M:%S")
        log_info "Resume time reached (limit expired at $expires_at_readable, resuming at $resume_at_readable)"
        return 0
    else
        local time_remaining=$((resume_timestamp - current_timestamp))
        local time_remaining_min=$(( (time_remaining + 59) / 60 ))
        log_debug "Rate limit not yet expired. Time remaining: ~${time_remaining_min}m"
    fi
    
    return 1
}

# Function to run as daemon
run_daemon() {
    log_info "Starting rate limit monitor daemon"
    
    while true; do
        if check_resume_time; then
            log_info "Executing scheduled resume"
            
            # Send resume command to Claude Code terminal
            "$CC_TOOLS_DIR/utils/send-to-claude.sh" "resume"
            
            # Clean up the state file
            rm -f "$RATE_LIMITED_STATE_FILE"
            
            # Send notification
            if [ -f "$CONFIG_FILE" ]; then
                local sms_enabled=$(jq -r '.sms_enabled // false' "$CONFIG_FILE" 2>/dev/null)
                if [ "$sms_enabled" = "true" ]; then
                    "$CC_TOOLS_DIR/sms/sms-sender.sh" "Claude Code rate limit expired - the session is now resumed" "completion" &
                fi
            fi
            
            log_info "Resume completed"
        fi
        
        # Use configured check interval
        local check_interval=60  # default 1 minute
        if [ -f "$CONFIG_FILE" ]; then
            check_interval=$(jq -r '.resume_check_interval // 60' "$CONFIG_FILE" 2>/dev/null)
        fi
        sleep "$check_interval"
    done
}

# Function to clean up on exit
cleanup() {
    log_info "Rate limit monitor stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
case "${1:-}" in
    "--daemon")
        run_daemon
        ;;
    *)
        echo "Usage: $0 [--daemon]"
        exit 1
        ;;
esac
