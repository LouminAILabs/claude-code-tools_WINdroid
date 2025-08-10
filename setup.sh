#!/bin/bash

# SMS Notification Setup Script
# Guides users through initial SMS configuration and testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_TOOLS_DIR="$SCRIPT_DIR"
CONFIG_FILE="$CC_TOOLS_DIR/config/config.json"
SETTINGS_LOCAL_FILE="${PWD}/.claude/settings.local.json"

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

# Function to print step headers
print_step() {
    local step="$1"
    local description="$2"
    echo ""
    print_color "$BLUE" "=== Step $step: $description ==="
    echo ""
}

# Function to ask yes/no questions
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    
    while true; do
        if [ "$default" = "y" ]; then
            read -p "$question [Y/n]: " answer
            answer=${answer:-y}
        else
            read -p "$question [y/N]: " answer
            answer=${answer:-n}
        fi
        
        case "$(echo "$answer" | tr '[:upper:]' '[:lower:]')" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) print_color "$RED" "Please answer yes or no." ;;
        esac
    done
}

# Function to validate phone number format
validate_phone_number() {
    local phone="$1"
    
    # Remove all non-digits
    local digits_only=$(echo "$phone" | sed 's/[^0-9]//g')
    
    # Check if it starts with 1 and has 11 digits, or has 10 digits
    if [[ "$digits_only" =~ ^1[0-9]{10}$ ]] || [[ "$digits_only" =~ ^[0-9]{10}$ ]]; then
        return 0
    fi
    
    return 1
}

# Function to format phone number
format_phone_number() {
    local phone="$1"
    local digits_only=$(echo "$phone" | sed 's/[^0-9]//g')
    
    # Add +1 prefix if needed
    if [[ "$digits_only" =~ ^[0-9]{10}$ ]]; then
        echo "+1$digits_only"
    elif [[ "$digits_only" =~ ^1[0-9]{10}$ ]]; then
        echo "+$digits_only"
    else
        echo "$phone"
    fi
}

# Function to check Messages app setup
check_messages_app() {
    print_step "1" "Checking Messages App Setup"
    
    # Check if Messages app exists
    if [ ! -d "/Applications/Messages.app" ] && [ ! -d "/System/Applications/Messages.app" ]; then
        print_color "$RED" "❌ Messages app not found. SMS notifications require Messages app."
        return 1
    fi
    
    print_color "$GREEN" "✅ Messages app found"
    
    # Check if Messages database exists
    if [ ! -f "$HOME/Library/Messages/chat.db" ]; then
        print_color "$YELLOW" "⚠️  Messages database not found. You may need to:"
        echo "   1. Open Messages app and sign in with your Apple ID"
        echo "   2. Send/receive at least one message to create the database"
        echo "   3. Enable 'Text Message Forwarding' in iPhone Settings > Messages"
        
        if ask_yes_no "Have you set up Messages app and want to continue?"; then
            return 0
        else
            return 1
        fi
    fi
    
    print_color "$GREEN" "✅ Messages database found"
    
    # Check database permissions
    if ! sqlite3 "$HOME/Library/Messages/chat.db" "SELECT COUNT(*) FROM message LIMIT 1" >/dev/null 2>&1; then
        print_color "$YELLOW" "⚠️  Cannot access Messages database. You need to:"
        echo "   1. Go to System Preferences > Security & Privacy > Privacy"
        echo "   2. Select 'Full Disk Access' from the left sidebar"
        echo "   3. Add Terminal (or your terminal app) to the list"
        echo "   4. Restart your terminal"
        
        if ask_yes_no "Have you granted Full Disk Access and want to continue?"; then
            # Test again
            if sqlite3 "$HOME/Library/Messages/chat.db" "SELECT COUNT(*) FROM message LIMIT 1" >/dev/null 2>&1; then
                print_color "$GREEN" "✅ Messages database is now accessible"
                return 0
            else
                print_color "$RED" "❌ Still cannot access Messages database"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    print_color "$GREEN" "✅ Messages database is accessible"
    return 0
}

# Function to load existing configuration values
load_existing_config() {
    if [ -f "$CONFIG_FILE" ]; then
        EXISTING_USER_PHONE=$(jq -r '.user_phone // ""' "$CONFIG_FILE" 2>/dev/null)
        EXISTING_CONTACTS=($(jq -r '.contacts[]? // empty' "$CONFIG_FILE" 2>/dev/null))
        EXISTING_AUTO_RESUME=$(jq -r '.auto_resume // false' "$CONFIG_FILE" 2>/dev/null)
        EXISTING_RESUME_CHECK_INTERVAL=$(jq -r '.resume_check_interval // 60' "$CONFIG_FILE" 2>/dev/null)
        EXISTING_SMS_CHECK_INTERVAL=$(jq -r '.sms_check_interval // 30' "$CONFIG_FILE" 2>/dev/null)
        EXISTING_SMS_ENABLED=$(jq -r '.sms_enabled // true' "$CONFIG_FILE" 2>/dev/null)
        EXISTING_SCREENSHOT_ENABLED=$(jq -r '.screenshot_enabled // false' "$CONFIG_FILE" 2>/dev/null)
        CONFIG_EXISTS=true
        
        print_color "$GREEN" "✅ Found existing configuration with:"
        echo "   • User phone: $EXISTING_USER_PHONE"
        echo "   • Contacts: ${EXISTING_CONTACTS[*]}"
        echo "   • Auto-resume: $EXISTING_AUTO_RESUME"
        echo "   • SMS enabled: $EXISTING_SMS_ENABLED"
        echo "   • Screenshot enabled: $EXISTING_SCREENSHOT_ENABLED"
        if [ "$EXISTING_AUTO_RESUME" = "true" ]; then
            echo "   • Resume check interval: $EXISTING_RESUME_CHECK_INTERVAL seconds"
            echo "   • SMS check interval: $EXISTING_SMS_CHECK_INTERVAL seconds"
        fi
        echo ""
    else
        CONFIG_EXISTS=false
        # Set empty defaults
        EXISTING_USER_PHONE=""
        EXISTING_CONTACTS=()
        EXISTING_AUTO_RESUME=false
        EXISTING_RESUME_CHECK_INTERVAL=60
        EXISTING_SMS_CHECK_INTERVAL=30
        EXISTING_SMS_ENABLED=true
        EXISTING_SCREENSHOT_ENABLED=false
    fi
}

# Function to configure phone numbers
configure_phone_numbers() {
    print_step "2" "Configure Phone Numbers"
    
    # Get user's phone number
    if [ "$CONFIG_EXISTS" = "true" ] && [ -n "$EXISTING_USER_PHONE" ]; then
        echo "Enter your phone number (the one associated with your Apple ID/iMessage):"
        echo "Current: $EXISTING_USER_PHONE"
    else
        echo "Enter your phone number (the one associated with your Apple ID/iMessage):"
    fi
    
    while true; do
        if [ "$CONFIG_EXISTS" = "true" ] && [ -n "$EXISTING_USER_PHONE" ]; then
            read -p "Your phone number [$EXISTING_USER_PHONE]: " user_phone
            user_phone=${user_phone:-$EXISTING_USER_PHONE}
        else
            read -p "Your phone number: " user_phone
        fi
        
        if [ -z "$user_phone" ]; then
            print_color "$RED" "Phone number cannot be empty"
            continue
        fi
        
        if validate_phone_number "$user_phone"; then
            user_phone=$(format_phone_number "$user_phone")
            print_color "$GREEN" "✅ Phone number formatted as: $user_phone"
            break
        else
            print_color "$RED" "❌ Invalid phone number format. Please use: +1234567890 or 234-567-8900"
        fi
    done
    
    # Get authorized contacts
    echo ""
    echo "Enter phone numbers that can send commands to Claude Code."
    echo "These are the numbers that can control Claude Code via SMS replies."
    
    local contacts=()
    local contact_num=1
    
    # Pre-populate with existing contacts if they exist
    if [ "$CONFIG_EXISTS" = "true" ] && [ ${#EXISTING_CONTACTS[@]} -gt 0 ]; then
        echo ""
        echo "Current authorized contacts:"
        for i in "${!EXISTING_CONTACTS[@]}"; do
            echo "  $((i+1)). ${EXISTING_CONTACTS[i]}"
        done
        echo ""
        
        if ask_yes_no "Keep existing contacts and skip adding new ones?" "y"; then
            contacts=("${EXISTING_CONTACTS[@]}")
        else
            echo "Press Enter with empty input to finish adding contacts."
        fi
    else
        echo "Press Enter with empty input to finish adding contacts."
    fi
    
    # Only ask for new contacts if we're not keeping existing ones
    if [ ${#contacts[@]} -eq 0 ]; then
        while true; do
            read -p "Contact #$contact_num (or Enter to finish): " contact_phone
            
            if [ -z "$contact_phone" ]; then
                if [ ${#contacts[@]} -eq 0 ]; then
                    print_color "$YELLOW" "⚠️  No authorized contacts added. You won't be able to reply to SMS notifications."
                    if ask_yes_no "Add at least one contact?"; then
                        continue
                    fi
                fi
                break
            fi
            
            if validate_phone_number "$contact_phone"; then
                contact_phone=$(format_phone_number "$contact_phone")
                contacts+=("$contact_phone")
                print_color "$GREEN" "✅ Added contact: $contact_phone"
                ((contact_num++))
            else
                print_color "$RED" "❌ Invalid phone number format. Please use: +1234567890 or 234-567-8900"
            fi
        done
    fi
    
    # If no contacts, add user's own number
    if [ ${#contacts[@]} -eq 0 ]; then
        contacts+=("$user_phone")
        print_color "$YELLOW" "📱 Added your own number as authorized contact"
    fi
    
    echo ""
    print_color "$GREEN" "📱 Your phone: $user_phone"
    print_color "$GREEN" "👥 Authorized contacts: ${contacts[*]}"
    
    # Store in variables for later use
    USER_PHONE="$user_phone"
    CONTACTS=("${contacts[@]}")
}


# Function to configure auto-resume
configure_auto_resume() {
    print_step "3" "Configure Auto-Resume"
    
    echo "Auto-resume allows Claude Code to automatically continue after rate limits expire."
    echo ""
    
    # Show current setting if config exists
    local default_auto_resume="y"
    if [ "$CONFIG_EXISTS" = "true" ]; then
        echo "Current setting: Auto-resume is $([ "$EXISTING_AUTO_RESUME" = "true" ] && echo "enabled" || echo "disabled")"
        default_auto_resume=$([ "$EXISTING_AUTO_RESUME" = "true" ] && echo "y" || echo "n")
    fi
    
    if ask_yes_no "Enable auto-resume after rate limits?" "$default_auto_resume"; then
        AUTO_RESUME=true
        
        echo "How often should we check for expired rate limits? (in seconds)"
        local default_interval=60
        if [ "$CONFIG_EXISTS" = "true" ]; then
            default_interval="$EXISTING_RESUME_CHECK_INTERVAL"
        fi
        while true; do
            read -p "Check interval [$default_interval]: " interval
            interval=${interval:-$default_interval}
            
            if [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 30 ]; then
                RESUME_CHECK_INTERVAL="$interval"
                break
            else
                print_color "$RED" "❌ Please enter a number >= 30"
            fi
        done
        
        echo "How often should we check for new SMS messages? (in seconds)"
        local default_sms_interval=30
        if [ "$CONFIG_EXISTS" = "true" ]; then
            default_sms_interval="$EXISTING_SMS_CHECK_INTERVAL"
        fi
        while true; do
            read -p "SMS check interval [$default_sms_interval]: " sms_interval
            sms_interval=${sms_interval:-$default_sms_interval}
            
            if [[ "$sms_interval" =~ ^[0-9]+$ ]] && [ "$sms_interval" -ge 5 ]; then
                SMS_CHECK_INTERVAL="$sms_interval"
                break
            else
                print_color "$RED" "❌ Please enter a number >= 5"
            fi
        done
    else
        AUTO_RESUME=false
        # Keep existing intervals even if auto-resume is disabled
        if [ "$CONFIG_EXISTS" = "true" ]; then
            RESUME_CHECK_INTERVAL="$EXISTING_RESUME_CHECK_INTERVAL"
            SMS_CHECK_INTERVAL="$EXISTING_SMS_CHECK_INTERVAL"
        else
            RESUME_CHECK_INTERVAL=60
            SMS_CHECK_INTERVAL=30
        fi
    fi
    
    print_color "$GREEN" "✅ Auto-resume: $AUTO_RESUME"
    if [ "$AUTO_RESUME" = "true" ]; then
        print_color "$GREEN" "✅ Check interval: $RESUME_CHECK_INTERVAL seconds"
        print_color "$GREEN" "✅ SMS check interval: $SMS_CHECK_INTERVAL seconds"
    fi
}

# Function to configure screenshot settings
configure_screenshot() {
    print_step "4" "Configure Screenshot Settings"
    
    echo "Screenshot functionality sends a terminal screenshot along with SMS notifications."
    echo "This helps you see the current state of Claude Code when you receive notifications."
    echo ""
    
    # Show current setting if config exists
    local default_screenshot="n"
    if [ "$CONFIG_EXISTS" = "true" ]; then
        echo "Current setting: Screenshot is $([ "$EXISTING_SCREENSHOT_ENABLED" = "true" ] && echo "enabled" || echo "disabled")"
        default_screenshot=$([ "$EXISTING_SCREENSHOT_ENABLED" = "true" ] && echo "y" || echo "n")
    fi
    
    if ask_yes_no "Enable screenshot with SMS notifications?" "$default_screenshot"; then
        SCREENSHOT_ENABLED=true
        print_color "$GREEN" "✅ Screenshots will be sent with SMS notifications"
        echo ""
        print_color "$YELLOW" "📝 IMPORTANT: Screenshots require additional permissions:"
        echo "   1. Grant Screen Recording permission to your terminal app:"
        echo "      System Settings → Privacy & Security → Screen Recording"
        echo "      → Add Terminal (or iTerm/iTerm2)"
        echo "   2. Grant Accessibility permission to your terminal app:"
        echo "      System Settings → Privacy & Security → Accessibility"
        echo "      → Add Terminal (or iTerm/iTerm2)"
        echo "   3. Prevent screen from turning off while away:"
        echo "      System Settings → Lock Screen → Start Screen Saver When inactive → Never"
        echo "      System Settings → Lock Screen → Turn display off on power adapter when inactive → Never"
        echo "   4. Restart your terminal app after granting permissions"
        echo ""
        print_color "$YELLOW" "💡 Tip: You can dim your screen brightness to save power while keeping it on"
    else
        SCREENSHOT_ENABLED=false
        print_color "$GREEN" "✅ Screenshots disabled - only text notifications will be sent"
    fi
}

# Function to create configuration file
create_config_file() {
    print_step "5" "Creating Configuration File"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Convert contacts array to JSON
    local contacts_json="[]"
    if [ ${#CONTACTS[@]} -gt 0 ]; then
        contacts_json=$(printf '%s\n' "${CONTACTS[@]}" | jq -R . | jq -s .)
    fi
    
    # Create configuration
    local config=$(jq -n \
        --arg user_phone "$USER_PHONE" \
        --argjson contacts "$contacts_json" \
        --argjson auto_resume "$AUTO_RESUME" \
        --argjson check_interval "$RESUME_CHECK_INTERVAL" \
        --argjson sms_interval "$SMS_CHECK_INTERVAL" \
        --argjson screenshot_enabled "$SCREENSHOT_ENABLED" \
        '{
            user_phone: $user_phone,
            contacts: $contacts,
            sms_enabled: true,
            auto_resume: $auto_resume,
            resume_check_interval: $check_interval,
            sms_check_interval: $sms_interval,
            max_message_length: 160,
            screenshot_enabled: $screenshot_enabled
        }')
    
    echo "$config" > "$CONFIG_FILE"
    print_color "$GREEN" "✅ Configuration saved to: $CONFIG_FILE"
}

# Function to test SMS sending
test_sms_sending() {
    print_step "6" "Testing SMS Functionality"
    
    if ask_yes_no "Send a test SMS to verify everything works?" "y"; then
        print_color "$YELLOW" "📤 Sending test message..."
        
        local test_message="Claude Code SMS test - setup completed successfully!"
        
        if "$CC_TOOLS_DIR/sms/sms-sender.sh" "$test_message" "completion"; then
            print_color "$GREEN" "✅ Test message sent!"
            echo "Check your phone to see if you received the test message."
            echo "If you didn't receive it, check:"
            echo "  - Messages app is signed in with correct Apple ID"
            echo "  - Text Message Forwarding is enabled on iPhone"
            echo "  - Contact exists in Messages app"
        else
            print_color "$RED" "❌ Failed to send test message"
            echo "This might be due to:"
            echo "  - Messages app not signed in"
            echo "  - Contact not found in Messages app"
            echo "  - AppleScript permissions not granted"
        fi
    fi
}

# Function to update permissions
update_permissions() {
    print_step "7" "Updating Permissions"
    
    if [ ! -f "$SETTINGS_LOCAL_FILE" ]; then
        print_color "$YELLOW" "⚠️  settings.local.json not found, creating basic permissions"
        echo '{"permissions": {"allow": [], "deny": []}}' > "$SETTINGS_LOCAL_FILE"
    fi
    
    # Add required permissions
    local permissions_to_add=(
        "Bash(osascript:*)"
        "Bash(sqlite3:*)"
        "Bash(jq:*)"
        "Bash($CC_TOOLS_DIR/sms/sms-sender.sh:*)"
        "Bash($CC_TOOLS_DIR/sms/sms-receiver.sh:*)"
        "Bash($CC_TOOLS_DIR/auto_resume/rate-limit-monitor.sh:*)"
    )
    
    for permission in "${permissions_to_add[@]}"; do
        # Check if permission already exists
        if ! jq -e --arg perm "$permission" '.permissions.allow | index($perm)' "$SETTINGS_LOCAL_FILE" >/dev/null; then
            # Add permission
            jq --arg perm "$permission" '.permissions.allow += [$perm]' "$SETTINGS_LOCAL_FILE" > "${SETTINGS_LOCAL_FILE}.tmp" && mv "${SETTINGS_LOCAL_FILE}.tmp" "$SETTINGS_LOCAL_FILE"
            print_color "$GREEN" "✅ Added permission: $permission"
        fi
    done
    
    print_color "$GREEN" "✅ Permissions updated"
}

# Function to show setup summary
show_summary() {
    print_step "8" "Setup Complete!"
    
    echo ""
    print_color "$GREEN" "🎉 SMS Notification System is now configured!"
    echo ""
    echo "Summary of your configuration:"
    echo "• User phone: $USER_PHONE"
    echo "• Authorized contacts: ${CONTACTS[*]}"
    echo "• Auto-resume: $AUTO_RESUME"
    if [ "$AUTO_RESUME" = "true" ]; then
        echo "• Check interval: $RESUME_CHECK_INTERVAL seconds"
    fi
    echo "• Screenshot with SMS: $SCREENSHOT_ENABLED"
    echo ""
    print_color "$BLUE" "📤 SMS Notifications:"
    echo "• SMS notifications are sent automatically via Claude Code hooks"
    echo "• No additional setup required for sending notifications"
    if [ "$SCREENSHOT_ENABLED" = "true" ]; then
        echo "• Screenshots will be sent automatically with SMS notifications"
    fi
    echo ""
    print_color "$BLUE" "🔧 Testing and Management:"
    echo "• Test SMS system: $CC_TOOLS_DIR/sms/test-sms.sh"
    echo "• Modify settings: $CC_TOOLS_DIR/setup.sh --reconfigure"
    echo ""
    print_color "$YELLOW" "💡 Note: The SMS receiver daemon runs independently and needs to be"
    print_color "$YELLOW" "    started manually when you want to receive SMS commands."
}

# Function to reconfigure existing setup
reconfigure_setup() {
    print_color "$YELLOW" "🔧 Reconfiguring SMS Notification System"
    
    # Load existing configuration first
    load_existing_config
    
    if [ "$CONFIG_EXISTS" = "true" ]; then
        echo ""
        echo "What would you like to change?"
        echo "1) Phone numbers (user phone and authorized contacts)"
        echo "2) Auto-resume settings"
        echo "3) Screenshot settings"
        echo "4) All settings (full reconfiguration)"
        echo "5) View current configuration and exit"
        echo ""
        
        while true; do
            read -p "Choose option (1-5): " choice
            case "$choice" in
                1)
                    print_color "$BLUE" "📱 Reconfiguring phone numbers only..."
                    # Use existing auto-resume and screenshot settings
                    AUTO_RESUME="$EXISTING_AUTO_RESUME"
                    RESUME_CHECK_INTERVAL="$EXISTING_RESUME_CHECK_INTERVAL"
                    SMS_CHECK_INTERVAL="$EXISTING_SMS_CHECK_INTERVAL"
                    SCREENSHOT_ENABLED="$EXISTING_SCREENSHOT_ENABLED"
                    configure_phone_numbers
                    create_config_file
                    print_color "$GREEN" "✅ Phone numbers updated successfully!"
                    exit 0
                    ;;
                2)
                    print_color "$BLUE" "⚡ Reconfiguring auto-resume settings only..."
                    # Use existing phone and screenshot settings
                    USER_PHONE="$EXISTING_USER_PHONE"
                    CONTACTS=("${EXISTING_CONTACTS[@]}")
                    SCREENSHOT_ENABLED="$EXISTING_SCREENSHOT_ENABLED"
                    configure_auto_resume
                    create_config_file
                    print_color "$GREEN" "✅ Auto-resume settings updated successfully!"
                    exit 0
                    ;;
                3)
                    print_color "$BLUE" "📸 Reconfiguring screenshot settings only..."
                    # Use existing phone and auto-resume settings
                    USER_PHONE="$EXISTING_USER_PHONE"
                    CONTACTS=("${EXISTING_CONTACTS[@]}")
                    AUTO_RESUME="$EXISTING_AUTO_RESUME"
                    RESUME_CHECK_INTERVAL="$EXISTING_RESUME_CHECK_INTERVAL"
                    SMS_CHECK_INTERVAL="$EXISTING_SMS_CHECK_INTERVAL"
                    configure_screenshot
                    create_config_file
                    print_color "$GREEN" "✅ Screenshot settings updated successfully!"
                    exit 0
                    ;;
                4)
                    print_color "$BLUE" "🔄 Running full reconfiguration..."
                    break
                    ;;
                5)
                    echo ""
                    echo "Current configuration:"
                    jq . "$CONFIG_FILE"
                    exit 0
                    ;;
                *)
                    print_color "$RED" "Invalid choice. Please select 1-5."
                    ;;
            esac
        done
    fi
    
    # Run full setup
    run_setup
}

# Function to run the complete setup
run_setup() {
    print_color "$BLUE" "📱 Claude Code SMS Notification Setup"
    print_color "$BLUE" "======================================"
    echo ""
    print_color "$YELLOW" "This script will help you set up SMS notifications for Claude Code."
    print_color "$YELLOW" "You will be able to receive text messages when Claude Code needs input"
    print_color "$YELLOW" "or completes tasks, and reply with commands to control Claude Code."
    echo ""
    
    # Load existing configuration to use as defaults
    load_existing_config
    
    if ! ask_yes_no "Ready to begin setup?" "y"; then
        print_color "$YELLOW" "Setup cancelled."
        exit 0
    fi
    
    # Run setup steps
    if ! check_messages_app; then
        print_color "$RED" "❌ Messages app setup failed. Please fix the issues and run setup again."
        exit 1
    fi
    
    configure_phone_numbers
    configure_auto_resume
    configure_screenshot
    create_config_file
    test_sms_sending
    update_permissions
    show_summary
}

# Main execution
case "${1:-}" in
    "--reconfigure")
        reconfigure_setup
        ;;
    "--test-config")
        if [ -f "$CONFIG_FILE" ]; then
            echo "Current SMS configuration:"
            jq . "$CONFIG_FILE"
            
            # Validate configuration
            "$CC_TOOLS_DIR/sms/sms-sender.sh" --test
        else
            print_color "$RED" "❌ No SMS configuration found. Run setup first."
            exit 1
        fi
        ;;
    *)
        run_setup
        ;;
esac