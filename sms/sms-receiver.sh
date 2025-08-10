#!/bin/bash

# SMS Receiver - Monitor Messages database for incoming replies
# Usage: sms-receiver.sh [--debug] [--daemon] [--check-once]

# Parse debug flag before sourcing logging utilities
if [[ "$1" == "--debug" ]]; then
    export CLAUDE_DEBUG="true"
    shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
MESSAGES_DB="$HOME/Library/Messages/chat.db"
LAST_CHECK_FILE="$CC_TOOLS_DIR/logs/cc-tools-last-check"
PROCESSED_MESSAGES_FILE="$CC_TOOLS_DIR/logs/cc-tools-processed-messages"
DAEMON_STATS_FILE="$CC_TOOLS_DIR/logs/cc-tools-daemon-stats"

# Source centralized utilities
source "$CC_TOOLS_DIR/utils/logging.sh"
source "$CC_TOOLS_DIR/utils/validation.sh"

# Function to validate configuration
validate_config() {
    validate_sms_config "$CONFIG_FILE" && validate_messages_db "$MESSAGES_DB"
}

# Function to check if sender is authorized
is_authorized_sender() {
    local sender="$1"
    log_debug "Checking if sender '$sender' is authorized"
    
    if jq -e --arg sender "$sender" '.contacts | index($sender)' "$CONFIG_FILE" >/dev/null 2>&1; then
        log_debug "Sender is authorized"
        return 0
    else
        log_debug "Sender is not authorized"
        return 1
    fi
}

# Function to take screenshot of Claude terminal and send via SMS
take_and_send_screenshot() {
    local sender="$1"
    "$CC_TOOLS_DIR/sms/screenshot.sh" "$sender"
}

# Function to check if message was already processed
is_message_processed() {
    local message_id="$1"
    
    if [ ! -f "$PROCESSED_MESSAGES_FILE" ]; then
        return 1  # Not processed
    fi
    
    grep -q "^${message_id}:" "$PROCESSED_MESSAGES_FILE" 2>/dev/null
}

# Function to mark message as processed
mark_message_processed() {
    local message_id="$1"
    local timestamp="$2"
    local sender="$3"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$PROCESSED_MESSAGES_FILE")"
    
    # Add message to processed list with timestamp and sender for debugging
    echo "${message_id}:${timestamp}:${sender}" >> "$PROCESSED_MESSAGES_FILE"
    
    # Keep only last 100 processed messages to prevent file growth
    if [ -f "$PROCESSED_MESSAGES_FILE" ]; then
        tail -n 100 "$PROCESSED_MESSAGES_FILE" > "${PROCESSED_MESSAGES_FILE}.tmp" && 
        mv "${PROCESSED_MESSAGES_FILE}.tmp" "$PROCESSED_MESSAGES_FILE"
    fi
    
    log_debug "Marked message $message_id as processed"
}

# Function to execute SMS command
execute_sms_command() {
    local message="$1"
    local sender="$2"
    local message_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]')

    if [[ "$message_lower" == cc* ]]; then
        # Remove 'cc' (case insensitive) and any following whitespace
        local command_to_send=$(echo "${message}" | sed -E 's/^[Cc][Cc][[:space:]]*//g')
        command_to_send=$(echo "$command_to_send" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') # trim whitespace

        # Check if the command after trimming 'cc' is 'status'
        if [[ "$(echo "$command_to_send" | tr '[:upper:]' '[:lower:]')" == "status" ]]; then
            log_info "Received status request from $sender"
            take_and_send_screenshot "$sender"
            return
        fi

        if [ -n "$command_to_send" ]; then
            log_info "Sending command to Claude Code from $sender: '$command_to_send'"
            
            # Send command and capture exit code
            if "$CC_TOOLS_DIR/utils/send-to-claude.sh" "$command_to_send"; then
                log_info "Command sent successfully to Claude Code"
                # Send success confirmation SMS
                "$CC_TOOLS_DIR/sms/sms-sender.sh" "✅ Command sent: '$command_to_send'" "notification" "$sender"
            else
                log_error "Failed to send command to Claude Code"
                # Send error notification SMS  
                "$CC_TOOLS_DIR/sms/sms-sender.sh" "❌ Failed to send command: '$command_to_send'" "error" "$sender"
            fi
        else
            log_warn "Empty command received from $sender."
            # Send warning SMS for empty command
            "$CC_TOOLS_DIR/sms/sms-sender.sh" "⚠️ Empty command received" "error" "$sender"
        fi
    fi
}

# Function to get last check time as a human-readable string
get_last_check_time_str() {
    if [ -f "$LAST_CHECK_FILE" ]; then
        cat "$LAST_CHECK_FILE"
    else
        date -v-5M '+%Y-%m-%d %H:%M:%S'
    fi
}

# Function to get the last check time as an Apple Core Data timestamp
get_last_check_apple_timestamp() {
    local last_check_str
    last_check_str=$(get_last_check_time_str)

    local last_check_unix
    last_check_unix=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_check_str" "+%s")

    local apple_epoch_diff=978307200
    local apple_timestamp=$(((last_check_unix - apple_epoch_diff) * 1000000000))
    
    echo "$apple_timestamp"
}

# Function to update last check timestamp
update_last_check_time() {
    date '+%Y-%m-%d %H:%M:%S' > "$LAST_CHECK_FILE"
}

# Function to update last check timestamp to a specific time
update_last_check_time_to() {
    local timestamp="$1"
    echo "$timestamp" > "$LAST_CHECK_FILE"
    log_debug "Updated last check time to: $timestamp"
}


# Function to update daemon statistics
update_daemon_stats() {
    local operation="$1"  # check, success, error, lock_failure, message_processed
    local count="${2:-1}"
    
    mkdir -p "$(dirname "$DAEMON_STATS_FILE")"
    
    if [ ! -f "$DAEMON_STATS_FILE" ]; then
        cat > "$DAEMON_STATS_FILE" <<EOF
{
  "start_time": "$(date '+%Y-%m-%d %H:%M:%S')",
  "checks": 0,
  "successful_queries": 0,
  "query_errors": 0,
  "lock_failures": 0,
  "messages_processed": 0,
  "last_update": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
    fi
    
    # Update the specific counter
    local temp_file="${DAEMON_STATS_FILE}.tmp"
    jq --arg op "$operation" --argjson count "$count" --arg timestamp "$(date '+%Y-%m-%d %H:%M:%S')" \
       '.[$op] += $count | .last_update = $timestamp' \
       "$DAEMON_STATS_FILE" > "$temp_file" && mv "$temp_file" "$DAEMON_STATS_FILE"
}

# Function to execute SQLite query with retry logic and exponential backoff
execute_sqlite_query_with_retry() {
    local query="$1"
    local max_retries=5
    local base_delay=0.1
    local max_delay=2.0
    local attempt=1
    local delay=$base_delay
    
    while [ $attempt -le $max_retries ]; do
        log_debug "SQLite query attempt $attempt/$max_retries"
        
        local result
        local exit_code
        result=$(sqlite3 -separator '|' "$MESSAGES_DB" "$query" 2>/dev/null)
        exit_code=$?
        
        case $exit_code in
            0)
                # Success
                log_debug "SQLite query succeeded on attempt $attempt"
                echo "$result"
                return 0
                ;;
            5)
                # SQLITE_BUSY - database is locked
                update_daemon_stats "lock_failures"
                log_debug "SQLite database locked (attempt $attempt/$max_retries), retrying in ${delay}s"
                sleep "$delay"
                
                # Exponential backoff with jitter
                delay=$(awk "BEGIN {printf \"%.2f\", $delay * 2}")
                if (( $(echo "$delay > $max_delay" | bc -l) )); then
                    delay=$max_delay
                fi
                # Add random jitter (±10%)
                delay=$(awk "BEGIN {srand(); printf \"%.2f\", $delay * (0.9 + rand() * 0.2)}")
                ;;
            *)
                # Other error
                update_daemon_stats "query_errors"
                log_error "SQLite query failed with exit code $exit_code (attempt $attempt)"
                if [ $attempt -eq $max_retries ]; then
                    return $exit_code
                fi
                sleep "$delay"
                ;;
        esac
        
        attempt=$((attempt + 1))
    done
    
    log_error "SQLite query failed after $max_retries attempts"
    return 1
}

# Function to check for new messages
check_new_messages() {
    update_daemon_stats "checks"
    
    # RACE CONDITION FIX: Capture query start time with buffer before reading last check timestamp
    # This ensures we don't miss messages that arrive during the query-update window
    local query_start_time
    query_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    local last_check_str
    last_check_str=$(get_last_check_time_str)
    
    log_debug "Checking for messages since: $last_check_str (query started at: $query_start_time)"
    
    # Use SQLite's built-in datetime functions for better precision
    # Add 5-second overlap to prevent missing messages and 1-second buffer for race conditions
    local query="
        WITH time_bounds AS (
            SELECT 
                datetime('$last_check_str', '-5 seconds') as last_check_with_overlap,
                datetime('$query_start_time', '+1 second') as query_end
        )
        SELECT 
            message.ROWID,
            REPLACE(REPLACE(message.text, '|', '&#124;'), CHAR(10), '\\n') as text, 
            COALESCE(handle.id, 'UNKNOWN') as handle_id, 
            datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') as timestamp,
            message.date as apple_timestamp
        FROM message 
        JOIN handle ON message.handle_id = handle.ROWID 
        CROSS JOIN time_bounds
        WHERE datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') > time_bounds.last_check_with_overlap
        AND datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') <= time_bounds.query_end
        AND message.is_from_me = 0
        AND message.text IS NOT NULL
        AND message.text != ''
        AND handle.id IS NOT NULL
        AND handle.id != ''
        ORDER BY message.date ASC
        LIMIT 50"
    
    local messages
    messages=$(execute_sqlite_query_with_retry "$query")
    local sqlite_exit_code=$?
    
    if [ $sqlite_exit_code -ne 0 ]; then
        log_error "SQLite query failed after retries - not updating timestamp to avoid missing messages"
        return 1
    fi
    
    update_daemon_stats "successful_queries"
    
    
    if [ -z "$messages" ]; then
        log_debug "No new messages found"
    else
        local message_count=0
        local processed_count=0
        local duplicate_count=0
        while IFS='|' read -r row_id text sender timestamp apple_ts; do
            if [ -z "$text" ] || [ "$text" = "NULL" ] || [ -z "$sender" ] || [ "$sender" = "NULL" ]; then
                log_debug "Skipping message with missing data: row_id='$row_id', text='${text:0:20}...', sender='$sender'"
                continue
            fi
            
            # Restore escaped characters
            text=$(echo "$text" | sed 's/&#124;/|/g' | sed 's/\\n/\n/g')
            
            message_count=$((message_count + 1))
            
            # Check for duplicates
            if is_message_processed "$row_id"; then
                duplicate_count=$((duplicate_count + 1))
                log_debug "Skipping duplicate message (ID: $row_id)"
                continue
            fi
            
            if is_authorized_sender "$sender"; then
                log_info "Processing authorized message (ID: $row_id) from $sender: ${text:0:50}..."
                execute_sms_command "$text" "$sender"
                mark_message_processed "$row_id" "$timestamp" "$sender"
                update_daemon_stats "messages_processed"
                processed_count=$((processed_count + 1))
            else
                log_warn "Ignoring message from unauthorized sender: $sender"
                # Still mark unauthorized messages as processed to avoid reprocessing them
                mark_message_processed "$row_id" "$timestamp" "$sender"
            fi
        done <<< "$messages"
        
        if [ $duplicate_count -gt 0 ]; then
            log_info "Found $message_count messages: $processed_count processed, $duplicate_count duplicates skipped"
        else
            log_info "Processed $processed_count new messages"
        fi
    fi
    
    # RACE CONDITION FIX: Use query start time with small buffer instead of current time
    # This prevents missing messages that arrived during processing
    local update_time
    update_time=$(date -j -v+1S -f "%Y-%m-%d %H:%M:%S" "$query_start_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$query_start_time")
    update_last_check_time_to "$update_time"
}

# Function to run as daemon
run_daemon() {
    log_info "Starting SMS receiver daemon"
    
    # Initialize daemon statistics
    update_daemon_stats "checks" 0  # Initialize counters
    
    # Reset last check time to current time to avoid processing old messages
    log_info "Resetting SMS last check time to current time to skip old messages"
    update_last_check_time
    
    local check_count=0
    
    while true; do
        if validate_config; then
            check_new_messages
        fi
        
        check_count=$((check_count + 1))
        # Log heartbeat with statistics every 10 checks (5 minutes with 30s interval)
        if [ $((check_count % 10)) -eq 0 ]; then
            local stats
            if [ -f "$DAEMON_STATS_FILE" ]; then
                local successful_queries lock_failures query_errors messages_processed
                successful_queries=$(jq -r '.successful_queries // 0' "$DAEMON_STATS_FILE" 2>/dev/null || echo "0")
                lock_failures=$(jq -r '.lock_failures // 0' "$DAEMON_STATS_FILE" 2>/dev/null || echo "0")
                query_errors=$(jq -r '.query_errors // 0' "$DAEMON_STATS_FILE" 2>/dev/null || echo "0")
                messages_processed=$(jq -r '.messages_processed // 0' "$DAEMON_STATS_FILE" 2>/dev/null || echo "0")
                
                stats="queries=$successful_queries, lock_fails=$lock_failures, errors=$query_errors, messages=$messages_processed"
            else
                stats="stats unavailable"
            fi
            log_info "SMS receiver heartbeat: checked $check_count times ($stats)"
        fi
        
        local check_interval
        check_interval=$(jq -r '.sms_check_interval // 30' "$CONFIG_FILE" 2>/dev/null)
        sleep "$check_interval"
    done
}

# Function to clean up on exit
cleanup() {
    log_info "SMS receiver daemon stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
case "${1:-}" in
    "--daemon")
        run_daemon
        ;;
    "--check-once")
        if validate_config; then
            check_new_messages
        fi
        ;;
    "--test")
        echo "Testing SMS receiver configuration..."
        if validate_config; then
            echo "✅ Configuration is valid"
            echo "📱 Authorized contacts: $(jq -r '.contacts | join(", ")' "$CONFIG_FILE")"
            echo "📬 Messages database: $MESSAGES_DB"
            echo "🔍 Last check: $(get_last_check_time_str)"
            
            if sqlite3 "$MESSAGES_DB" "SELECT COUNT(*) FROM message LIMIT 1" >/dev/null 2>&1; then
                echo "✅ Messages database accessible"
            else
                echo "❌ Cannot access Messages database. Grant Full Disk Access to your terminal."
            fi
            
            # Display daemon statistics if available
            if [ -f "$DAEMON_STATS_FILE" ]; then
                echo ""
                echo "📊 Daemon Statistics:"
                start_time=$(jq -r '.start_time // "N/A"' "$DAEMON_STATS_FILE" 2>/dev/null)
                successful_queries=$(jq -r '.successful_queries // 0' "$DAEMON_STATS_FILE" 2>/dev/null)
                lock_failures=$(jq -r '.lock_failures // 0' "$DAEMON_STATS_FILE" 2>/dev/null)
                query_errors=$(jq -r '.query_errors // 0' "$DAEMON_STATS_FILE" 2>/dev/null)
                messages_processed=$(jq -r '.messages_processed // 0' "$DAEMON_STATS_FILE" 2>/dev/null)
                last_update=$(jq -r '.last_update // "N/A"' "$DAEMON_STATS_FILE" 2>/dev/null)
                
                echo "   Start time: $start_time"
                echo "   Successful queries: $successful_queries"
                echo "   Lock failures: $lock_failures"
                echo "   Query errors: $query_errors"
                echo "   Messages processed: $messages_processed"
                echo "   Last update: $last_update"
            fi
            
        else
            echo "❌ Configuration validation failed"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [--daemon|--check-once|--test]"
        echo ""
        echo "Options:"
        echo "  --daemon      Run continuously checking for new messages"
        echo "  --check-once  Check once for new messages and exit"
        echo "  --test        Test configuration, database access, and show diagnostics"
        exit 1
        ;;
esac