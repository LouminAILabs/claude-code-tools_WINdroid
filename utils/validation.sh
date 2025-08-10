#!/bin/bash

# Shared validation utilities for claude-code-tools
# Usage: source this file and use validation functions

# Function to validate basic configuration
validate_basic_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "Invalid JSON in configuration file: $config_file"
        return 1
    fi
    
    return 0
}

# Function to validate SMS configuration
validate_sms_config() {
    local config_file="$1"
    
    if ! validate_basic_config "$config_file"; then
        return 1
    fi
    
    local enabled=$(jq -r '.sms_enabled // false' "$config_file" 2>/dev/null)
    if [ "$enabled" != "true" ]; then
        log_info "SMS notifications are disabled"
        return 1
    fi
    
    local contacts=$(jq -r '.contacts[]' "$config_file" 2>/dev/null)
    if [ -z "$contacts" ]; then
        log_error "No contacts configured for SMS notifications"
        return 1
    fi
    
    return 0
}

# Function to validate Messages database access
validate_messages_db() {
    local messages_db="${1:-$HOME/Library/Messages/chat.db}"
    
    if ! command -v sqlite3 &> /dev/null; then
        log_error "sqlite3 command not found. Please install it."
        return 1
    fi
    
    if [ ! -r "$messages_db" ]; then
        log_error "Messages database not readable: $messages_db"
        log_error "Please grant Full Disk Access to your terminal application in System Settings -> Privacy & Security."
        return 1
    fi
    
    if ! sqlite3 "$messages_db" "SELECT COUNT(*) FROM message LIMIT 1" >/dev/null 2>&1; then
        log_error "Cannot query Messages database. Check permissions."
        return 1
    fi
    
    return 0
}