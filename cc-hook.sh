#!/bin/bash

# Claude Code Hook

# Parse debug flag before sourcing logging utilities
if [[ "$1" == "--debug" ]]; then
    export CLAUDE_DEBUG="true"
    shift
fi

# Get project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$SCRIPT_DIR"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
RATE_LIMITED_STATE_FILE="$CC_TOOLS_DIR/logs/rate-limited-state.json"

# Source centralized logging utilities
source "$CC_TOOLS_DIR/utils/logging.sh"

log_debug "claude-code-tools hook started."
log_debug "Arguments: $@"

# Read JSON input from stdin
input=$(cat)
log_debug "Received input: $input"

# Extract event information
hook_event_name=$(echo "$input" | jq -r '.hook_event_name // empty')
message=$(echo "$input" | jq -r '.message // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

log_debug "Hook event: $hook_event_name"
log_debug "Session ID: $session_id"
log_debug "Transcript path: $transcript_path"

# Function to get local IANA timezone name
get_local_iana_timezone() {
    # For macOS, readlink is often reliable
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ -h /etc/localtime ]]; then
            local tz_path
            tz_path=$(readlink /etc/localtime)
            if [[ "$tz_path" == *"zoneinfo/"* ]]; then
                echo "$tz_path" | sed 's|.*/zoneinfo/||'
                return
            fi
        fi
        # Fallback for macOS
        systemsetup -gettimezone | awk -F': ' '{print $2}'
        return
    fi

    # For many Linux systems with systemd
    if command -v timedatectl &> /dev/null; then
        timedatectl show --property=Timezone --value
        return
    fi

    # Fallback for other Linux systems
    if [[ -f /etc/timezone ]]; then
        cat /etc/timezone
        return
    elif [[ -h /etc/localtime ]]; then
        readlink /etc/localtime | sed 's|.*/zoneinfo/||'
        return
    fi

    # If all else fails, return UTC as a safe default
    echo "UTC"
}

# Function to extract rate limit expiration time from the last line of the transcript
extract_rate_limit_expire_at() {
    local transcript_path="$1"
    log_debug "Extracting rate limit expiration from transcript: $transcript_path"

    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        log_debug "Transcript path is empty or file does not exist."
        echo "0"
        return
    fi

    local last_line=$(tail -n 1 "$transcript_path")
    if [ -z "$last_line" ]; then
        log_debug "Transcript file is empty."
        echo "0"
        return
    fi

    local message_text=$(echo "$last_line" | jq -r '.message.content[0].text // empty')
    log_debug "Last message text from transcript: $message_text"

    if [[ "$message_text" == "Claude AI usage limit reached"* ]]; then
        log_debug "Rate limit pattern found in message text."
        echo "$message_text" | cut -d'|' -f2
    else
        log_debug "No rate limit pattern found in last message."
        echo "0"
    fi
}

# Function to save rate limit state
save_rate_limit_state() {
    local expires_at="$1"
    log_debug "Saving rate limit state with expires_at: $expires_at"
    local state_data=$(jq -n \
        --arg expires_at "$expires_at" \
        '{ 
            expires_at: ($expires_at | tonumber)
        }')
    echo "$state_data" > "$RATE_LIMITED_STATE_FILE"
    log_info "Rate limit state saved with expires_at: $expires_at"
}

# Function to check if SMS should be sent for this message
should_send_sms() {
    local message="$1"
    log_debug "Checking if SMS should be sent"
    if [ ! -f "$CONFIG_FILE" ]; then
        log_debug "Config file not found. Not sending SMS."
        return 1
    fi
    local sms_enabled=$(jq -r '.sms_enabled // false' "$CONFIG_FILE" 2>/dev/null)
    if [ "$sms_enabled" != "true" ]; then
        log_debug "SMS is disabled in config. Not sending SMS."
        return 1
    fi
    return 0
}

# Function to check if auto-resume is enabled
is_auto_resume_enabled() {
    log_debug "Checking if auto-resume is enabled..."
    if [ ! -f "$CONFIG_FILE" ]; then
        log_debug "Config file not found. Auto-resume disabled."
        return 1
    fi
    local auto_resume=$(jq -r '.auto_resume // false' "$CONFIG_FILE" 2>/dev/null)
    if [ "$auto_resume" != "true" ]; then
        log_debug "Auto-resume is false in config. Auto-resume disabled."
        return 1
    fi
    log_debug "Auto-resume is enabled."
    return 0
}

# Function to send SMS notification
send_sms() {
    local message="$1"
    local event_type="$2"
    if should_send_sms "$message"; then
        log_info "Sending SMS for event '$event_type': ${message:0:100}..."
        "$CC_TOOLS_DIR/sms/sms-sender.sh" "$message" "$event_type" &
        if [ "$event_type" = "notification" ]; then
            local screenshot_enabled=$(jq -r '.screenshot_enabled // false' "$CONFIG_FILE" 2>/dev/null)
            if [ "$screenshot_enabled" = "true" ]; then
                log_info "Screenshot enabled, sending screenshot for notification event"
                local user_phone=$(jq -r '.user_phone // ""' "$CONFIG_FILE" 2>/dev/null)
                if [ -n "$user_phone" ]; then
                    "$CC_TOOLS_DIR/sms/screenshot.sh" "$user_phone" &
                fi
            fi
        fi
    else
        log_info "Skipping SMS for event '$event_type'."
    fi
}

# Main event processing logic
case "$hook_event_name" in
    "Stop")
        log_debug "Processing 'Stop' event."
        local rate_limit_expires_at
        rate_limit_expires_at=$(extract_rate_limit_expire_at "$transcript_path")
        if [ "$rate_limit_expires_at" -gt 0 ]; then
            if is_auto_resume_enabled; then
                log_warn "Rate limit detected. Expires at: $rate_limit_expires_at"
                save_rate_limit_state "$rate_limit_expires_at"
                
                local local_tz
                local_tz=$(get_local_iana_timezone)
                log_debug "Determined local timezone: $local_tz"
                
                local readable_time
                local tz_abbr
                if command -v gdate >/dev/null 2>&1; then
                    readable_time=$(TZ="$local_tz" gdate -d "@$rate_limit_expires_at" "+%-I%p")
                    tz_abbr=$(TZ="$local_tz" gdate -d "@$rate_limit_expires_at" "+%Z")
                else
                    readable_time=$(TZ="$local_tz" date -r "$rate_limit_expires_at" "+%-I%p")
                    tz_abbr=$(TZ="$local_tz" date -r "$rate_limit_expires_at" "+%Z")
                fi

                local friendly_tz_name
                friendly_tz_name=$(echo "$local_tz" | sed 's|.*/||' | sed 's|_| |g')

                notification_msg="Claude AI usage limit reached, will be resumed automatically at ${readable_time} ${friendly_tz_name} time (${tz_abbr})"
                send_sms "$notification_msg" "error"
            else
                log_info "Rate limit detected but auto-resume is disabled"
                send_sms "Claude hit rate limit. Auto-resume is disabled." "error"
            fi
        else
            stop_message="Claude completed its current task."
            send_sms "$stop_message" "Stop"
        fi
        ;;
        
    "Notification")
        log_debug "Processing 'Notification' event."
        notification_message="$message"
        log_debug "Final notification message: ${notification_message:0:200}..."
        if [ -n "$notification_message" ]; then
            send_sms "$notification_message" "notification"
        else
            log_debug "Notification message is empty. Nothing to do."
        fi
        ;;
        
    *)
        log_debug "Hook event '$hook_event_name' is not handled by this hook. Ignoring."
        ;;
esac

log_debug "claude-code-tools hook finished."
exit 0