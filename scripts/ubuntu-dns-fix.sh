#!/bin/bash

LOG_FILE="/var/log/ubuntu-dns-fix.log"
DEFAULT_TARGET_DOMAIN="google.com" # A reliable domain to test resolution
DEFAULT_INTERFACE_NAME="eth0"      # Your specific network interface

# Assign arguments or use default values
TARGET_DOMAIN="${1:-$DEFAULT_TARGET_DOMAIN}"
INTERFACE_NAME="${2:-$DEFAULT_INTERFACE_NAME}"  

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | sudo tee -a "$LOG_FILE" > /dev/null
}
# Function to check DNS resolution using host against systemd-resolved's stub
check_system_dns() {
    log_message "Attempting to resolve $TARGET_DOMAIN using systemd-resolved (via 127.0.0.53)..."

    # Capture the output of nslookup
    NSLOOKUP_OUTPUT=$(nslookup "$TARGET_DOMAIN" 127.0.0.53 2>&1)

    # Check if the specific error message is present
    # shellcheck disable=SC2063
    if echo "$NSLOOKUP_OUTPUT" | grep -q "*** Can't find $TARGET_DOMAIN: No answer"; then
        log_message "System-wide DNS resolution for $TARGET_DOMAIN is NOT working (specific 'No answer' error found)."
        return 1 # DNS is not working due to the specific error
    elif echo "$NSLOOKUP_OUTPUT" | grep -q "connection timed out; no servers could be reached"; then
        log_message "System-wide DNS resolution for $TARGET_DOMAIN is NOT working (connection timed out)."
        return 1 # DNS is not working due to timeout
    elif echo "$NSLOOKUP_OUTPUT" | grep -q "NXDOMAIN"; then
        log_message "System-wide DNS resolution for $TARGET_DOMAIN is NOT working (NXDOMAIN - domain does not exist)."
        return 1 # DNS is not working due to NXDOMAIN
    elif ! echo "$NSLOOKUP_OUTPUT" | grep -q "Address:"; then
        # If no specific error, but also no "Address:" line (meaning no successful resolution)
        log_message "System-wide DNS resolution for $TARGET_DOMAIN is NOT working (no address found in output)."
        return 1
    else
        log_message "System-wide DNS resolution for $TARGET_DOMAIN is working."
        return 0 # DNS is working
    fi
}
# Function to check DNS servers configured for the interface
check_interface_dns() {
    log_message "Checking DNS servers for interface $INTERFACE_NAME using resolvectl dns..."
    DNS_SERVERS=$(resolvectl dns "$INTERFACE_NAME" | awk '/DNS Servers:/ {getline; print $0}' | xargs)

    if [ -z "$DNS_SERVERS" ]; then
        log_message "WARNING: No DNS servers found for interface $INTERFACE_NAME."
        return 1
    else
        log_message "DNS servers for $INTERFACE_NAME: $DNS_SERVERS"
        # You could add a more specific check here if you expect certain IPs
        # e.g., if [[ ! "$DNS_SERVERS" =~ "192.168.1.1" ]]; then ...
        return 0
    fi
}
# Main logic
if check_interface_dns; then
    log_message "DNS looks good on the interface. No action needed."
else
    log_message "DNS is not on the interface. Initiating troubleshooting and potential restart..."

    # Check if the interface has DNS servers configured
    if ! check_interface_dns; then
        log_message "Problem detected: Interface $INTERFACE_NAME is missing DNS server configuration or has an issue."
        log_message "This might be the root cause. Attempting to restart systemd-resolved."
        sudo systemctl restart systemd-resolved
        if [ $? -eq 0 ]; then
            log_message "systemd-resolved restarted successfully. Waiting 5 seconds and re-checking..."
            sleep 5
            if check_system_dns; then
                log_message "DNS is now working after restarting systemd-resolved."
            else
                log_message "WARNING: DNS is still not working after restarting systemd-resolved."
                log_message "Further investigation into $INTERFACE_NAME DNS configuration is needed."
                log_message "--- Troubleshooting steps to consider: ---"
                log_message "1. Check NetworkManager/Netplan configuration for $INTERFACE_NAME."
                log_message "2. Manually set DNS for $INTERFACE_NAME using 'sudo resolvectl dns $INTERFACE_NAME <IP>'"
                log_message "3. Review 'journalctl -u systemd-resolved.service' for errors."
                log_message "4. Check DHCP server for correct DNS server assignment."
                log_message "-----------------------------------------"
            fi
        else
            log_message "ERROR: Failed to restart systemd-resolved. Check system logs for details."
            log_message "Run 'sudo journalctl -xe' for more information."
        fi
    else
        log_message "DNS resolution is failing despite $INTERFACE_NAME having configured DNS servers."
        log_message "This suggests an issue with the configured DNS servers or connectivity to them."
        log_message "Attempting to restart systemd-resolved as a first step."
        sudo systemctl restart systemd-resolved
        if [ $? -eq 0 ]; then
            log_message "systemd-resolved restarted successfully. Waiting 5 seconds and re-checking..."
            sleep 5
            if check_system_dns; then
                log_message "DNS is now working after restarting systemd-resolved."
            else
                log_message "WARNING: DNS is still not working after restarting systemd-resolved."
                log_message "--- Troubleshooting steps to consider: ---"
                log_message "1. Test configured DNS servers manually: 'dig @<server_ip> google.com'."
                log_message "2. Check network connectivity to those DNS servers (ping)."
                log_message "3. Review 'journalctl -u systemd-resolved.service' for errors."
                log_message "-----------------------------------------"
            fi
        else
            log_message "ERROR: Failed to restart systemd-resolved. Check system logs for details."
            log_message "Run 'sudo journalctl -xe' for more information."
        fi
    fi
fi
