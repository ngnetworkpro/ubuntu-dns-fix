# 🚀 systemd-resolved DNS Health Checker

A robust Bash script designed to monitor and automatically restore DNS resolution on Ubuntu 22.04 LTS systems that use `systemd-resolved` for DNS management and `NetworkManager` for network configuration.

This script detects common DNS failures, attempts to fix them by restarting `systemd-resolved`, and provides detailed, context-aware troubleshooting guidance directly in the logs if the issue persists.

## ✨ Features

* **Proactive DNS Monitoring**: Verifies system-wide DNS resolution by explicitly querying `systemd-resolved`'s stub resolver (`127.0.0.53`).
* **Intelligent Failure Detection**: Recognizes specific `nslookup` error patterns like "No answer", "connection timed out", or "NXDOMAIN".
* **Interface DNS Check**: Checks if the specified network interface (e.g., `eth0`) has DNS servers configured according to `systemd-resolved`.
* **Automated Recovery**: Automatically restarts the `systemd-resolved` service upon detecting a DNS failure.
* **Comprehensive Logging**: Records all actions and outcomes to `/var/log/dns_check.log` for easy review.
* **Contextual Troubleshooting**: Provides highly relevant manual troubleshooting steps in the logs, especially when DNS configuration issues are linked to `NetworkManager` (common with `renderer: NetworkManager` in Netplan).

## ⚙️ Prerequisites

* **Operating System**: Ubuntu 22.04 LTS (or a similar `systemd`-based Linux distribution).
* **DNS Resolver**: `systemd-resolved` service must be running and enabled.
* **Network Renderer**: `NetworkManager` must be managing your network interfaces (as indicated by `renderer: NetworkManager` in your `/etc/netplan/*.yaml` file).
* **Utilities**:
    * `host` (typically part of `bind-utils` or `bind9-dnsutils` package).
    * `grep`, `awk`, `echo`, `sudo`, `systemctl`, `date`, `sleep`, `tee`.

## 📦 Installation & Setup

1.  **Clone the Repository (or download the script):**
    ```bash
    git clone [https://github.com/ngnetworkpro/ubuntu-dns-fix.git](https://github.com/ngnetworkpro/ubuntu-dns-fix.git)
    cd ubuntu-dns-fix
    ```

2.  **Save the Script:**
    Save the script content into a file, for example, `check_dns_health.sh`.
    ```bash
    nano check_dns_health.sh
    ```
    (Paste the script content from the previous response here)

3.  **Make the Script Executable:**
    ```bash
    chmod +x check_dns_health.sh
    ```

4.  **Place the Script:**
    Move the script to a suitable location, e.g., `/usr/local/bin/` or `/opt/scripts/`.
    ```bash
    sudo mv check_dns_health.sh /usr/local/bin/
    ```

5.  **Configure Script Variables:**
    Open the script (`sudo nano /usr/local/bin/check_dns_health.sh`) and adjust the following variables if needed:
    * `TARGET_DOMAIN="google.com"`: The domain used to test DNS resolution. Choose a reliable, always-up domain.
    * `INTERFACE_NAME="eth0"`: Your primary network interface name (e.g., `eth0`, `enp0s3`, `ens33`). You can find this using `ip a`.

## 🚀 Usage

You can run the script manually for immediate checks or automate it for continuous monitoring.

### Manual Run

To run the script once:

```bash
sudo /usr/local/bin/check_dns_health.sh
```

Check the output in the log file:

```bash
tail -f /var/log/dns_check.log
```

### Automation
For continuous monitoring and self-healing, it's highly recommended to automate the script's execution.

#### Option 1: Using Cron (Simple Periodic Check)
Cron is good for basic periodic tasks.

1.  **Edit your crontab:**
    ```bash
    sudo crontab -e
    ```

2.  **Add the following line to run the script every 5 minutes:**
    ```
    */5 * * * * /usr/local/bin/check_dns_health.sh >> /var/log/dns_check.log 2>&1
    ```
    This redirects all output to `/var/log/dns_check.log`.

#### Option 2: Using systemd Timer (More Robust & Integrated)
Systemd timers are preferred for better integration with systemd and more precise control over execution.

1.  **Create a systemd Service Unit File:**

    Create `/etc/systemd/system/ubuntu-dns-fix.service` with the following content:

    ```ini, TOML
    [Unit]
    Description=DNS Health Checker Service
    After=network-online.target systemd-resolved.service

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/check_dns_health.sh
    StandardOutput=journal
    StandardError=journal
    ``` 
    
2.  **Create a systemd Timer Unit File:**

    Create /etc/systemd/system/ubuntu-dns-fix.timer with the following content:

    ```ini, TOML
    [Unit]
    Description=Run DNS Health Checker every 5 minutes

    [Timer]
    OnBootSec=1min   # Run 1 minute after boot
    OnUnitActiveSec=5min # Run every 5 minutes after the service was last active
    AccuracySec=1s   # Be precise with timing

    [Install]
    WantedBy=timers.target
    
    ```
3. **Reload systemd, Enable, and Start the Timer:**

    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable ubuntu-dns-fix.timer
    sudo systemctl start ubuntu-dns-fix.timer
    ```
    
4.  **You can check the timer status with:**

    ```bash
    sudo systemctl list-timers | grep ubuntu-dns-fix
    ```

5. **And service logs with:**

    ```bash
    sudo journalctl -u ubuntu-dns-fix.service -f
    ```
    
## 📄 Logging
All script output is appended to /var/log/dns_check.log. Regularly inspect this file, especially if you experience persistent DNS issues, as it contains detailed messages and troubleshooting guidance.

```bash
tail -f /var/log/dns_check.log
```

## 🔍 Troubleshooting (If the script doesn't resolve it)
If the script detects a problem and restarts `systemd-resolved` but DNS still fails, the logs in `/var/log/dns_check.log` will contain specific "WARNING" messages with recommended troubleshooting steps. These steps are crucial and often point to configuration issues outside of `systemd-resolved` itself, particularly with `NetworkManager`.

### Common Scenarios & Manual Checks
#### Scenario 1: `resolvectl dns eth0` shows "No DNS servers reported..."

This indicates `systemd-resolved` is not receiving DNS server information for your interface from NetworkManager.

1.  **Identify your NetworkManager connection name for `eth0`:**

    ```Bash
    nmcli connection show
    ```
    Look for a connection name associated with `eth0` (e.g., "Wired connection 1", or simply "eth0").

2.  **Examine NetworkManager connection settings for DNS:**
    Replace `<YOUR_CONNECTION_NAME>` with the name you found above.

    ```Bash

    nmcli connection show <YOUR_CONNECTION_NAME> | grep -E "ipv4.dns|ipv6.dns|ipv4.method|ipv6.method|ipv4.ignore-auto-dns|ipv6.ignore-auto-dns"
    ```
    
    + Check `ipv4.dns` / `ipv6.dns`: Are they empty when they should have IP addresses?
    + **CRITICAL**: If `ipv4.ignore-auto-dns` or `ipv6.ignore-auto-dns` is `yes` and you rely on DHCP for DNS, this is likely the problem. Set it to `no`:
    ```Bash

    sudo nmcli connection modify <YOUR_CONNECTION_NAME> ipv4.ignore-auto-dns no
    # For IPv6 if needed:
    # sudo nmcli connection modify <YOUR_CONNECTION_NAME> ipv6.ignore-auto-dns no
    ```
    
3.  **Re-activate the NetworkManager connection to apply changes:**

    ```Bash

    sudo nmcli connection up <YOUR_CONNECTION_NAME>
    ```
    
4.  **Restart NetworkManager service (if previous steps don't fix it):**

    ```Bash

    sudo systemctl restart NetworkManager
    ```

5.  **Review NetworkManager logs for errors:**

    ```Bash

    sudo journalctl -u NetworkManager.service -f
    ```

#### Scenario 2: DNS servers are configured (per resolvectl dns eth0), but resolution still fails

This suggests systemd-resolved has the DNS server IPs, but cannot reach or use them.

1. **Manually test the configured DNS servers:**
    From `resolvectl dns eth0` output, get the IP addresses of the DNS servers (e.g., `192.168.1.1`, `8.8.8.8`).

    ```Bash

    dig @<DNS_SERVER_IP> google.com
    ```
    Does this command work for each server? If not, those servers might be unresponsive or unreachable.

2. **Check network connectivity to those DNS servers:**

    ```Bash

    ping <DNS_SERVER_IP>
    ```
    Can you reach them? If not, check your routing, firewall, or physical network connection.

3. **Review `systemd-resolved` logs for errors:**

    ```Bash

    sudo journalctl -u systemd-resolved.service -f
    ```
    Look for messages indicating issues contacting upstream DNS servers, cache problems, etc.

4. **Check Firewall Rules:**
    Ensure your firewall (e.g., `ufw` or `iptables`) isn't blocking outgoing UDP port 53 (DNS) traffic.

    ```Bash

    sudo ufw status verbose
    ```
    
## 🤝 Contributing
Contributions are welcome! If you have suggestions for improvements, new features, or bug fixes, please open an issue or submit a pull request.

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
