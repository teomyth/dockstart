#!/bin/bash
#
# install.sh - Installer for dockstart
#
# This script installs the dockstart tool and configures it to run at system boot
# or WSL startup, depending on the environment.
#
# Version: 1.0.0

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# GitHub repository information
GITHUB_REPO="teomyth/dockstart"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

# Print a header
print_header() {
    echo -e "${BOLD}${BLUE}=== $1 ===${NC}"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}✗${NC} This script must be run as root (sudo)."
    exit 1
fi

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine if we need to download or use local files

# Define systemd service file content
SYSTEMD_SERVICE_CONTENT="[Unit]
Description=Start Docker containers with restart policy
After=docker.service
Requires=docker.service
ConditionPathExists=/usr/local/bin/dockstart

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dockstart --retry --force
RemainAfterExit=yes
StandardOutput=journal

[Install]
WantedBy=multi-user.target"

# Print header
print_header "Dockstart Installer"

# Detect installation method
is_piped_install=false

# Check if script is being sourced (piped through curl/wget)
# Method 1: Check if stdin is a terminal
if [ ! -t 0 ]; then
    is_piped_install=true
fi

# Method 2: Check if parent process is curl, wget, or similar
parent_process=$(ps -o comm= $PPID 2>/dev/null | tr -d ' ')
if [[ "$parent_process" == *"curl"* || "$parent_process" == *"wget"* || "$parent_process" == "sh" || "$parent_process" == "bash" ]]; then
    # If parent is shell, it might be a pipe from curl/wget
    if [ ! -t 0 ]; then
        is_piped_install=true
    fi
fi

# Method 3: Check if script was downloaded to a temporary location
if [[ "$SCRIPT_DIR" == *"/tmp/"* ]]; then
    is_piped_install=true
fi

if [ "$is_piped_install" = true ]; then
    echo -e "${CYAN}▶${NC} Running through pipe or download (curl/wget)"
else
    echo -e "${CYAN}▶${NC} Running in local environment"
fi

# Install dockstart script
echo -e "${CYAN}▶${NC} Installing dockstart to /usr/local/bin/dockstart..."

if [ "$is_piped_install" = true ]; then
    # Install from GitHub
    echo -e "${CYAN}▶${NC} Downloading dockstart from GitHub..."

    # Check if curl is available
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "${GITHUB_RAW_URL}/bin/dockstart" -o /usr/local/bin/dockstart; then
            echo -e "${RED}✗${NC} Failed to download dockstart from GitHub using curl"
            exit 1
        fi
    # Check if wget is available
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "${GITHUB_RAW_URL}/bin/dockstart" -O /usr/local/bin/dockstart; then
            echo -e "${RED}✗${NC} Failed to download dockstart from GitHub using wget"
            exit 1
        fi
    else
        echo -e "${RED}✗${NC} Neither curl nor wget is available. Please install one of them and try again."
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Successfully downloaded dockstart from GitHub"
else
    # Install from local directory
    if [ ! -f "$SCRIPT_DIR/bin/dockstart" ]; then
        echo -e "${RED}✗${NC} dockstart script not found at $SCRIPT_DIR/bin/dockstart"
        exit 1
    fi
    echo -e "${CYAN}▶${NC} Copying dockstart from local directory..."
    cp "$SCRIPT_DIR/bin/dockstart" /usr/local/bin/dockstart
    echo -e "${GREEN}✓${NC} Successfully copied dockstart from local directory"
fi

chmod +x /usr/local/bin/dockstart
echo -e "${GREEN}✓${NC} dockstart installed successfully"

# Check if we're running in WSL
is_wsl=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    is_wsl=true
    echo -e "${CYAN}▶${NC} WSL environment detected"
fi

# Configure for WSL
configure_wsl() {
    print_header "Configuring WSL Integration"
    echo -e "${CYAN}▶${NC} Setting up dockstart to run at WSL startup..."

    # Required parameters for dockstart
    REQUIRED_PARAMS="--retry --force"

    # Check if /etc/wsl.conf exists
    if [ ! -f /etc/wsl.conf ]; then
        echo -e "${CYAN}▶${NC} Creating /etc/wsl.conf file"
        cat > /etc/wsl.conf << EOF
[boot]
command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}
EOF
        echo -e "${GREEN}✓${NC} WSL configuration complete - dockstart will run at WSL startup"
        return 0
    fi

    # Check if [boot] section exists
    if grep -q "^\[boot\]" /etc/wsl.conf; then
        # Check if command is already set
        if grep -q "^command\s*=" /etc/wsl.conf; then
            # Get the current command line
            CURRENT_COMMAND=$(grep -A 5 "^\[boot\]" /etc/wsl.conf | grep "^command\s*=" | head -1)

            # Check if dockstart is already in the command
            if echo "$CURRENT_COMMAND" | grep -q "/usr/local/bin/dockstart"; then
                # Extract the current dockstart command
                DOCKSTART_CMD=$(echo "$CURRENT_COMMAND" | sed -E 's/^command\s*=\s*//')

                # Check if all required parameters are present
                MISSING_PARAMS=""
                for param in $REQUIRED_PARAMS; do
                    if ! echo "$DOCKSTART_CMD" | grep -q -- "$param"; then
                        MISSING_PARAMS="$MISSING_PARAMS $param"
                    fi
                done

                if [ -z "$MISSING_PARAMS" ]; then
                    # All required parameters are present
                    echo -e "${GREEN}✓${NC} dockstart is already properly configured in /etc/wsl.conf:"
                    echo "$CURRENT_COMMAND" | sed 's/^/  /'
                    echo -e "${GREEN}✓${NC} No changes needed to WSL configuration"
                    return 0
                else
                    # Some parameters are missing, attempt to update automatically
                    echo -e "${YELLOW}!${NC} dockstart is configured but missing required parameters in /etc/wsl.conf:"
                    echo "$CURRENT_COMMAND" | sed 's/^/  /'
                    echo -e "${CYAN}▶${NC} Attempting to update configuration automatically..."

                    # Check if the command is a simple dockstart command or part of a chain
                    if echo "$CURRENT_COMMAND" | grep -q "&&" || echo "$CURRENT_COMMAND" | grep -q "||" || echo "$CURRENT_COMMAND" | grep -q ";"; then
                        # Complex command, suggest manual update
                        echo -e "${YELLOW}!${NC} Your boot command appears to be part of a command chain."
                        echo -e "${YELLOW}!${NC} Please manually update your boot command to include:${MISSING_PARAMS}"
                        echo -e "  ${CYAN}Current:${NC} $CURRENT_COMMAND"
                        echo -e "  ${CYAN}Required parameters:${NC}${MISSING_PARAMS}"
                        return 1
                    else
                        # Simple command, update automatically
                        NEW_COMMAND="command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}"
                        sed -i "s|^command.*dockstart.*|$NEW_COMMAND|" /etc/wsl.conf
                        echo -e "${GREEN}✓${NC} Updated dockstart command in /etc/wsl.conf:"
                        echo "  $NEW_COMMAND"
                        return 0
                    fi
                fi
            else
                # dockstart not in command, check if we can append it
                echo -e "${YELLOW}!${NC} A boot command is already configured in /etc/wsl.conf:"
                echo "$CURRENT_COMMAND" | sed 's/^/  /'

                # Check if the command ends with a command terminator
                if echo "$CURRENT_COMMAND" | grep -qE ';\s*$'; then
                    # Command ends with semicolon, we can append
                    NEW_COMMAND="${CURRENT_COMMAND} /usr/local/bin/dockstart ${REQUIRED_PARAMS}"
                    sed -i "s|^command.*|$NEW_COMMAND|" /etc/wsl.conf
                    echo -e "${GREEN}✓${NC} Appended dockstart to existing command in /etc/wsl.conf:"
                    echo "  $NEW_COMMAND"
                    return 0
                else
                    # Suggest manual update with &&
                    echo -e "${YELLOW}!${NC} Please manually add dockstart to your boot command"
                    echo -e "  ${CYAN}Example:${NC} ${CURRENT_COMMAND} && /usr/local/bin/dockstart ${REQUIRED_PARAMS}"
                    return 1
                fi
            fi
        else
            # Add command under existing [boot] section
            echo -e "${CYAN}▶${NC} Adding dockstart to existing [boot] section in /etc/wsl.conf"
            sed -i "/^\[boot\]/a command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}" /etc/wsl.conf
            echo -e "${GREEN}✓${NC} WSL configuration complete - dockstart will run at WSL startup"
            return 0
        fi
    else
        # Add [boot] section and command
        echo -e "${CYAN}▶${NC} Adding [boot] section to /etc/wsl.conf"
        cat >> /etc/wsl.conf << EOF

[boot]
command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}
EOF
        echo -e "${GREEN}✓${NC} WSL configuration complete - dockstart will run at WSL startup"
        return 0
    fi
}

# Configure for systemd
configure_systemd() {
    print_header "Configuring Systemd Integration"
    echo -e "${CYAN}▶${NC} Setting up dockstart as a systemd service..."

    # Required parameters for dockstart in systemd
    REQUIRED_PARAMS="--retry --force"

    # Check if service file already exists
    if [ -f /etc/systemd/system/dockstart.service ]; then
        echo -e "${CYAN}▶${NC} Checking existing dockstart.service configuration..."

        # Check if the service file has the required parameters
        if grep -q "ExecStart=/usr/local/bin/dockstart" /etc/systemd/system/dockstart.service; then
            MISSING_PARAMS=""
            for param in $REQUIRED_PARAMS; do
                if ! grep -q -- "ExecStart=.*$param" /etc/systemd/system/dockstart.service; then
                    MISSING_PARAMS="$MISSING_PARAMS $param"
                fi
            done

            if [ -z "$MISSING_PARAMS" ]; then
                echo -e "${GREEN}✓${NC} dockstart.service is already properly configured"
            else
                echo -e "${YELLOW}!${NC} dockstart.service is missing required parameters:${MISSING_PARAMS}"
                echo -e "${CYAN}▶${NC} Updating service file with required parameters..."

                # Update the ExecStart line
                sed -i "s|ExecStart=/usr/local/bin/dockstart.*|ExecStart=/usr/local/bin/dockstart ${REQUIRED_PARAMS}|" /etc/systemd/system/dockstart.service

                echo -e "${GREEN}✓${NC} Service file updated with required parameters"
                echo -e "${CYAN}▶${NC} Reloading systemd daemon..."
                systemctl daemon-reload
                echo -e "${GREEN}✓${NC} systemd daemon reloaded"
            fi
        else
            echo -e "${YELLOW}!${NC} Existing service file does not appear to be for dockstart"
            echo -e "${CYAN}▶${NC} Creating new dockstart.service file..."
            echo "$SYSTEMD_SERVICE_CONTENT" > /etc/systemd/system/dockstart.service
            echo -e "${GREEN}✓${NC} Service file installed to /etc/systemd/system/dockstart.service"
            echo -e "${CYAN}▶${NC} Reloading systemd daemon..."
            systemctl daemon-reload
            echo -e "${GREEN}✓${NC} systemd daemon reloaded"
        fi
    else
        # Create service file
        echo -e "${CYAN}▶${NC} Creating dockstart.service file..."
        echo "$SYSTEMD_SERVICE_CONTENT" > /etc/systemd/system/dockstart.service
        echo -e "${GREEN}✓${NC} Service file installed to /etc/systemd/system/dockstart.service"
    fi

    # Check if service is enabled
    if systemctl is-enabled dockstart.service &>/dev/null; then
        echo -e "${GREEN}✓${NC} dockstart.service is already enabled"
    else
        echo -e "${CYAN}▶${NC} Enabling dockstart.service to start at boot..."
        systemctl enable dockstart.service
        echo -e "${GREEN}✓${NC} dockstart.service enabled - it will start automatically at boot"
    fi

    # Check if service is running
    if systemctl is-active dockstart.service &>/dev/null; then
        echo -e "${GREEN}✓${NC} dockstart.service is already running"
    else
        # Offer to start the service now
        read -p "Do you want to start dockstart service now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}▶${NC} Starting dockstart service..."
            systemctl start dockstart.service
            echo -e "${GREEN}✓${NC} dockstart service started"
        fi
    fi

    return 0
}

# Main installation logic
if [ "$is_wsl" = true ]; then
    configure_wsl
    wsl_result=$?

    if [ $wsl_result -eq 0 ]; then
        echo -e "${GREEN}✓${NC} WSL configuration complete"
        echo -e "${CYAN}▶${NC} You'll need to restart WSL for changes to take effect"
        echo -e "  ${CYAN}Restart command:${NC} wsl --shutdown (run from PowerShell)"
    else
        echo -e "${YELLOW}!${NC} WSL configuration requires manual adjustment as noted above"
    fi
else
    # Check if systemd is available
    if command -v systemctl >/dev/null 2>&1; then
        configure_systemd
        echo -e "${GREEN}✓${NC} systemd configuration complete"
    else
        echo -e "${YELLOW}!${NC} Neither WSL nor systemd detected"
        echo -e "${YELLOW}!${NC} You'll need to manually configure dockstart to run at startup"
        echo -e "  ${CYAN}Manual run:${NC} sudo /usr/local/bin/dockstart"
    fi
fi

echo
print_header "Installation Complete"
echo -e "${GREEN}✓${NC} dockstart is now installed at /usr/local/bin/dockstart"

# Installation complete - no additional info needed

exit 0
