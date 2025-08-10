#!/bin/bash

# Screenshot utility for Claude Code tools
# Usage: screenshot.sh <sender_phone> [screenshot_path]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"

# Source centralized logging utilities
source "$CC_TOOLS_DIR/utils/logging.sh"

# Function to take screenshot of Claude terminal and send via SMS
take_and_send_screenshot() {
    local sender="$1"
    local custom_screenshot_path="${2:-}"
    
    log_info "Taking screenshot of Claude terminal for $sender"
    
    # Get terminal configuration
    local terminal_app=$(jq -r '.terminal_app // "Terminal"' "$CONFIG_FILE")
    local claude_process_id=$(jq -r '.claude_terminal_process_id // empty' "$CONFIG_FILE")
    
    if [ -z "$claude_process_id" ]; then
        log_error "Claude terminal process ID not configured"
        "$CC_TOOLS_DIR/sms/sms-sender.sh" "Error: Claude terminal not configured. Run start.sh first." "notification"
        return 1
    fi
    
    # Create screenshots directory
    local screenshot_dir="$CC_TOOLS_DIR/logs/screenshots"
    mkdir -p "$screenshot_dir"
    
    # Generate unique filename or use custom path
    local screenshot_path
    if [ -n "$custom_screenshot_path" ]; then
        screenshot_path="$custom_screenshot_path"
    else
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        screenshot_path="$screenshot_dir/claude_status_$timestamp.png"
    fi
    
    # Take screenshot based on terminal type
    if [ "$terminal_app" = "Terminal" ]; then
        osascript <<EOF
        tell application "Terminal"
            activate
            try
                set claudeWindow to first window whose id is $claude_process_id
                delay 0.5
                
                -- Get window bounds for targeted screenshot
                tell application "System Events"
                    tell process "Terminal"
                        set frontmost to true
                        delay 0.2
                        set windowBounds to position of window 1
                        set windowSize to size of window 1
                        set x to item 1 of windowBounds
                        set y to item 2 of windowBounds
                        set w to item 1 of windowSize
                        set h to item 2 of windowSize
                    end tell
                end tell
                
                -- Take screenshot of specific window region
                set cropRegion to (x as string) & "," & (y as string) & "," & w & "," & h
                do shell script "screencapture -R " & cropRegion & " -x -t png '$screenshot_path'"
                
            on error
                display dialog "Could not find Claude terminal window"
            end try
        end tell
        
        # Optimize image size
        do shell script "sips -Z 1200 '$screenshot_path'"
EOF
    elif [ "$terminal_app" = "iTerm" ] || [ "$terminal_app" = "iTerm2" ]; then
        IFS=':' read -r window_num tab_num session_num <<< "$claude_process_id"
        osascript <<EOF
        tell application "$terminal_app"
            activate
            try
                select window $window_num
                select tab $tab_num of window $window_num
                delay 0.5
                
                -- Get window bounds for targeted screenshot
                tell application "System Events"
                    tell process "$terminal_app"
                        set frontmost to true
                        delay 0.2
                        set windowBounds to position of window $window_num
                        set windowSize to size of window $window_num
                        set x to item 1 of windowBounds
                        set y to item 2 of windowBounds
                        set w to item 1 of windowSize
                        set h to item 2 of windowSize
                    end tell
                end tell
                
                -- Take screenshot of specific window region
                set cropRegion to (x as string) & "," & (y as string) & "," & w & "," & h
                do shell script "screencapture -R " & cropRegion & " -x -t png '$screenshot_path'"
                
            on error
                display dialog "Could not find Claude iTerm session"
            end try
        end tell
        
        # Optimize image size
        do shell script "sips -Z 1200 '$screenshot_path'"
EOF
    else
        log_error "Unsupported terminal app: $terminal_app"
        return 1
    fi
    
    # Check if screenshot was created
    if [ -f "$screenshot_path" ]; then
        log_debug "Screenshot saved to: $screenshot_path"
        
        # Copy image to clipboard with proper image format
        log_debug "Copying screenshot to clipboard..."
        osascript -e "set the clipboard to (read (POSIX file \"$screenshot_path\") as «class PNGf»)"
        
        # Open Messages app to specific conversation
        log_debug "Opening Messages app to contact $sender"
        phone_clean=$(echo "$sender" | sed 's/[^0-9]//g')
        open "sms://$phone_clean"
        
        # Give Messages time to open and load conversation
        sleep 3
        
        # Check if we have assistive access before attempting automation
        if ! osascript -e 'tell application "System Events" to get processes' > /dev/null 2>&1; then
            log_warn "System Events requires assistive access. Go to System Preferences > Security & Privacy > Privacy > Accessibility and add Terminal (or your terminal app)."
            log_debug "Screenshot is copied to clipboard. Please manually paste (Cmd+V) and send in Messages."
            return 0
        fi
        
        # Try to automatically paste and send with better focus handling
        log_debug "Attempting to paste and send screenshot..."
        if osascript <<EOF
        tell application "Messages"
            activate
            delay 1
        end tell
        
        tell application "System Events"
            tell process "Messages"
                set frontmost to true
                delay 1
                -- Paste the image (Cmd+V)
                key code 9 using command down
                delay 3
                
                -- Send the message (Enter)
                key code 36
            end tell
        end tell
EOF
        then
            log_debug "Screenshot sent successfully via automation."
        else
            log_warn "Automation failed. Screenshot is on clipboard - please manually paste (Cmd+V) and send in Messages."
        fi
        
        # Clean up old screenshots (keep last 5) only if using default path
        if [ -z "$custom_screenshot_path" ]; then
            find "$screenshot_dir" -name "claude_status_*.png" -type f | sort -r | tail -n +6 | xargs rm -f
        fi
        
        log_info "Screenshot sent to $sender"
        return 0
    else
        log_error "Failed to create screenshot"
        "$CC_TOOLS_DIR/sms/sms-sender.sh" "Error: Failed to take screenshot" "notification"
        return 1
    fi
}

# Main execution when called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <sender_phone> [screenshot_path]"
        echo ""
        echo "Arguments:"
        echo "  sender_phone    Phone number to send screenshot to"
        echo "  screenshot_path Optional custom path for screenshot file"
        exit 1
    fi
    
    take_and_send_screenshot "$1" "$2"
fi