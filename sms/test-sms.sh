#!/bin/bash

# SMS Notification Testing Script - Simplified without message queue
# Usage: test-sms.sh [--basic|--integration|--receiver|--all]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
SESSION_STATE_FILE="$CC_TOOLS_DIR/logs/session-state.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    if [ "$result" = "PASS" ]; then
        print_color "$GREEN" "✅ $test_name"
    else
        print_color "$RED" "❌ $test_name"
        if [ -n "$details" ]; then
            print_color "$RED" "   $details"
        fi
    fi
}

# Function to run basic configuration tests
test_basic_config() {
    print_color "$BLUE" "📋 Running Basic Configuration Tests"
    echo ""
    
    # Test 1: SMS config file exists and is valid
    if [ -f "$CONFIG_FILE" ]; then
        if jq empty "$CONFIG_FILE" 2>/dev/null; then
            print_test_result "SMS config file valid" "PASS"
        else
            print_test_result "SMS config file valid" "FAIL" "Invalid JSON in config file"
        fi
    else
        print_test_result "SMS config file valid" "FAIL" "Config file not found"
    fi
    
    # Test 2: SMS enabled check
    local sms_enabled=$(jq -r '.sms_enabled // false' "$CONFIG_FILE" 2>/dev/null)
    if [ "$sms_enabled" = "true" ]; then
        print_test_result "SMS notifications enabled" "PASS"
    else
        print_test_result "SMS notifications enabled" "FAIL" "SMS is disabled in config"
    fi
    
    # Test 3: Contacts configured
    local contacts_count=$(jq -r '.contacts | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$contacts_count" -gt 0 ]; then
        print_test_result "Contacts configured ($contacts_count)" "PASS"
    else
        print_test_result "Contacts configured" "FAIL" "No contacts found"
    fi
    
    
    # Test 4: SMS sender script executable
    if [ -x "$CC_TOOLS_DIR/sms/sms-sender.sh" ]; then
        print_test_result "SMS sender script executable" "PASS"
    else
        print_test_result "SMS sender script executable" "FAIL"
    fi
    
    # Test 5: SMS sender test functionality
    if "$CC_TOOLS_DIR/sms/sms-sender.sh" --test >/dev/null 2>&1; then
        print_test_result "SMS sender test passes" "PASS"
    else
        print_test_result "SMS sender test passes" "FAIL"
    fi
    
    echo ""
}

# Function to test Messages app setup
test_messages_app() {
    print_color "$BLUE" "📱 Testing Messages App Setup"
    echo ""
    
    # Test 1: Messages app exists
    if [ -d "/Applications/Messages.app" ] || [ -d "/System/Applications/Messages.app" ]; then
        print_test_result "Messages app found" "PASS"
    else
        print_test_result "Messages app found" "FAIL"
    fi
    
    # Test 2: Messages database exists
    if [ -f "$HOME/Library/Messages/chat.db" ]; then
        print_test_result "Messages database found" "PASS"
    else
        print_test_result "Messages database found" "FAIL" "Open Messages app and sign in"
    fi
    
    # Test 3: Database accessibility
    if sqlite3 "$HOME/Library/Messages/chat.db" "SELECT COUNT(*) FROM message LIMIT 1" >/dev/null 2>&1; then
        print_test_result "Messages database accessible" "PASS"
    else
        print_test_result "Messages database accessible" "FAIL" "Grant Full Disk Access to Terminal"
    fi
    
    echo ""
}

# Function to test SMS receiver functionality
test_receiver() {
    print_color "$BLUE" "📨 Testing SMS Receiver Functionality"
    echo ""
    
    # Test 1: SMS receiver script executable
    if [ -x "$CC_TOOLS_DIR/sms/sms-receiver.sh" ]; then
        print_test_result "SMS receiver script executable" "PASS"
    else
        print_test_result "SMS receiver script executable" "FAIL"
    fi
    
    # Test 2: SMS receiver can validate config
    if "$CC_TOOLS_DIR/sms/sms-receiver.sh" --check-once >/dev/null 2>&1; then
        print_test_result "SMS receiver config validation" "PASS"
    else
        print_test_result "SMS receiver config validation" "FAIL"
    fi
    
    print_color "$YELLOW" "💡 To start SMS receiver daemon manually:"
    echo "   $CC_TOOLS_DIR/sms/sms-receiver.sh --daemon &"
    echo "OR"
    echo "   $CC_TOOLS_DIR/start.sh"
    echo ""
}

# Function to test integration
test_integration() {
    print_color "$BLUE" "🔗 Testing SMS Integration"
    echo ""
    
    # Test 1: Send test SMS
    print_color "$YELLOW" "📤 Sending test SMS message..."
    local test_message="Claude Code SMS test - $(date '+%H:%M:%S')"
    
    if "$CC_TOOLS_DIR/sms/sms-sender.sh" "$test_message" "completion"; then
        print_test_result "Test SMS sent" "PASS"
        print_color "$GREEN" "   Test message sent successfully!"
        print_color "$YELLOW" "   Check your phone for the message"
    else
        print_test_result "Test SMS sent" "FAIL"
    fi
    
    echo ""
}

# Function to test hooks configuration
test_hooks() {
    print_color "$BLUE" "🔗 Testing Hooks Configuration"
    echo ""
    
    # Test 1: Check if hooks are configured in settings.json
    local settings_file="${PWD}/.claude/settings.json"
    if [ -f "$settings_file" ]; then
        if jq -r '.hooks.Notification[0].hooks[] | select(.command | contains("cc-hook.sh")) | .command' "$settings_file" >/dev/null 2>&1; then
            print_test_result "Claude Code hook configured" "PASS"
        else
            print_test_result "Claude Code hook configured" "FAIL" "cc-hook.sh not found in settings.json"
        fi
        
        if jq -r '.hooks.Stop[0].hooks[] | select(.command | contains("cc-hook.sh")) | .command' "$settings_file" >/dev/null 2>&1; then
            print_test_result "Claude Code Stop hook configured" "PASS"
        else
            print_test_result "Claude Code Stop hook configured" "FAIL" "cc-hook.sh not found in Stop hooks"
        fi
    else
        print_test_result "Settings.json exists" "FAIL" "Settings file not found"
    fi
    
    echo ""
}

# Function to display summary and instructions
display_summary() {
    print_color "$BLUE" "📋 SMS Notification System Summary"
    echo ""
    
    print_color "$GREEN" "✅ Setup Complete! Here's how to use the SMS system:"
    echo ""
    echo "1. 📤 Sending SMS notifications:"
    echo "   - SMS notifications are sent automatically via hooks"
    echo "   - Test manually: ./sms/sms-sender.sh \"Test message\" \"completion\""
    echo ""
    echo "2. 📨 Receiving SMS commands (optional):"
    echo "   - Start receiver daemon: ./sms/sms-receiver.sh --daemon &"
    echo "   - Reply to SMS with: status, pause, resume, cancel, help"
    echo ""
    echo "3. 🔄 Auto-resume functionality:"
    echo "   - Automatically handles Claude API rate limits"
    echo "   - No manual intervention required"
    echo ""
    echo "4. ⚙️  Configuration files:"
    echo "   - SMS settings: ./config/sms-config.json"
    echo ""
    
    print_color "$YELLOW" "💡 Note: The SMS receiver daemon needs to be started manually."
    print_color "$YELLOW" "    You can add it to your startup scripts or run it when needed."
}

# Main execution
case "${1:-all}" in
    "--basic")
        test_basic_config
        ;;
    "--messages")
        test_messages_app
        ;;
    "--receiver")
        test_receiver
        ;;
    "--integration")
        test_integration
        ;;
    "--hooks")
        test_hooks
        ;;
    "--all"|"")
        test_basic_config
        test_messages_app
        test_receiver
        test_hooks
        test_integration
        display_summary
        ;;
    *)
        echo "Usage: $0 [--basic|--messages|--receiver|--integration|--hooks|--all]"
        echo ""
        echo "Test modes:"
        echo "  --basic       Test basic configuration"
        echo "  --messages    Test Messages app setup"
        echo "  --receiver    Test SMS receiver functionality"
        echo "  --integration Test SMS sending"
        echo "  --hooks       Test hooks configuration"
        echo "  --all         Run all tests (default)"
        exit 1
        ;;
esac