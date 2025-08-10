#!/bin/bash

# SMS Sender - Simplified AppleScript wrapper for sending SMS via Messages app
# Usage: sms-sender.sh "message" "event_type" [recipient]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"

# Source centralized utilities
source "$CC_TOOLS_DIR/utils/logging.sh"
source "$CC_TOOLS_DIR/utils/validation.sh"

# Function to validate configuration
validate_config() {
    validate_sms_config "$CONFIG_FILE"
}

# Function to truncate message to SMS limits
truncate_message() {
    local message="$1"
    local max_length=$(jq -r '.max_message_length // 160' "$CONFIG_FILE" 2>/dev/null)
    
    if [ ${#message} -gt "$max_length" ]; then
        echo "${message:0:$((max_length-3))}..."
    else
        echo "$message"
    fi
}

# Function to send SMS using AppleScript
send_sms_applescript() {
    local recipient="$1"
    local message="$2"
    
    # Create AppleScript to send message
    local applescript="
    tell application \"Messages\"
        set targetService to 1st account whose service type = iMessage
        set targetBuddy to participant \"$recipient\" of targetService
        send \"$message\" to targetBuddy
    end tell"
    
    # Execute AppleScript
    local result=$(osascript -e "$applescript" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_info "SMS sent successfully to $recipient"
        return 0
    else
        log_error "Failed to send SMS to $recipient: $result"
        return 1
    fi
}

# Function to add event type prefix to message
add_event_prefix() {
    local message="$1"
    local event_type="$2"
    
    case "$event_type" in
        "completion")
            echo "Claude Code ✅: $message"
            ;;
        "error")
            echo "Claude Code ❌: $message"
            ;;
        "input")
            echo "Claude Code ⏳: $message"
            ;;
        "notification")
            echo "Claude Code: $message"
            ;;
        "status")
            echo "Claude Code: $message"
            ;;
        *)
            echo "Claude Code: $message"
            ;;
    esac
}

# Main SMS sending function
send_sms() {
    local message="$1"
    local event_type="${2:-notification}"
    local specific_recipient="$3"
    
    # Validate configuration
    if ! validate_config; then
        return 1
    fi
    
    # Add prefix based on event type
    local prefixed_message=$(add_event_prefix "$message" "$event_type")
    
    # Truncate message if needed
    prefixed_message=$(truncate_message "$prefixed_message")
    
    # Determine recipients
    local recipients
    if [ -n "$specific_recipient" ]; then
        recipients="$specific_recipient"
    else
        recipients=$(jq -r '.contacts[]' "$CONFIG_FILE" 2>/dev/null)
    fi
    
    # Send to each recipient
    local success=0
    local total=0
    
    while IFS= read -r recipient; do
        if [ -n "$recipient" ]; then
            total=$((total + 1))
            log_info "Sending SMS to $recipient: ${prefixed_message:0:50}..."
            
            if send_sms_applescript "$recipient" "$prefixed_message"; then
                success=$((success + 1))
            fi
        fi
    done <<< "$recipients"
    
    if [ $success -eq $total ]; then
        log_info "All SMS messages sent successfully ($success/$total)"
        return 0
    elif [ $success -gt 0 ]; then
        log_warn "Some SMS messages failed ($success/$total successful)"
        return 1
    else
        log_error "All SMS messages failed (0/$total successful)"
        return 1
    fi
}

# Function to test SMS functionality
test_sms() {
    echo "Testing SMS configuration..."
    
    if ! validate_config; then
        echo "❌ SMS configuration is invalid"
        return 1
    fi
    
    echo "✅ SMS configuration is valid"
    
    local contacts=$(jq -r '.contacts[]' "$CONFIG_FILE" 2>/dev/null)
    echo "📱 Contacts configured:"
    while IFS= read -r contact; do
        echo "   - $contact"
    done <<< "$contacts"
    
    echo ""
    echo "Test completed. To send a test message, run:"
    echo "   $0 \"Test message\" \"completion\""
    
    return 0
}

# Main execution
case "${1:-}" in
    "--test")
        test_sms
        ;;
    "")
        echo "Usage: $0 \"message\" [event_type] [recipient]"
        echo ""
        echo "Event types: completion, error, input, notification, status"
        echo "Examples:"
        echo "       $0 \"Task completed successfully\" \"completion\""
        echo "       $0 \"Input required\" \"input\" \"+1234567890\""
        echo "       $0 --test"
        exit 1
        ;;
    *)
        send_sms "$1" "$2" "$3"
        ;;
esac