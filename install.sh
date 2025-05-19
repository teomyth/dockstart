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
    echo -e "==> ${BLUE}$1${NC}"
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
print_header "INSTALL"

# Detect installation method
is_piped_install=false

# Check if script is being sourced (piped through curl/wget)
if [ ! -t 0 ] || [[ "$(ps -o comm= $PPID 2>/dev/null | tr -d ' ')" == *"curl"* ||
                    "$(ps -o comm= $PPID 2>/dev/null | tr -d ' ')" == *"wget"* ||
                    "$(ps -o comm= $PPID 2>/dev/null | tr -d ' ')" == "sh" ||
                    "$(ps -o comm= $PPID 2>/dev/null | tr -d ' ')" == "bash" && ! -t 0 ]] ||
   [[ "$SCRIPT_DIR" == *"/tmp/"* ]]; then
    is_piped_install=true
    echo -e "+ ${CYAN}Source: Remote (GitHub)${NC}"
else
    echo -e "+ ${CYAN}Source: Local${NC}"
fi

# Install dockstart script
echo -e "+ ${CYAN}Copying to /usr/local/bin/dockstart${NC}"

if [ "$is_piped_install" = true ]; then
    # Install from GitHub
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "${GITHUB_RAW_URL}/bin/dockstart" -o /usr/local/bin/dockstart; then
            echo -e "${RED}✗${NC} Download failed (curl)"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "${GITHUB_RAW_URL}/bin/dockstart" -O /usr/local/bin/dockstart; then
            echo -e "${RED}✗${NC} Download failed (wget)"
            exit 1
        fi
    else
        echo -e "${RED}✗${NC} Neither curl nor wget is available"
        exit 1
    fi
else
    # Install from local directory
    if [ ! -f "$SCRIPT_DIR/bin/dockstart" ]; then
        echo -e "${RED}✗${NC} Script not found at $SCRIPT_DIR/bin/dockstart"
        exit 1
    fi
    cp "$SCRIPT_DIR/bin/dockstart" /usr/local/bin/dockstart
fi

chmod +x /usr/local/bin/dockstart
echo -e "${GREEN}Installation successful${NC}"

print_header "CONFIGURE"

# Check environment
is_wsl=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    is_wsl=true
    echo -e "+ ${CYAN}Environment: WSL${NC}"
else
    echo -e "+ ${CYAN}Environment: Linux${NC}"
fi

# Configure for WSL
configure_wsl() {
    # WSL configuration is handled in the main function

    # Required parameters for dockstart
    REQUIRED_PARAMS="--retry --force"

    # Check if /etc/wsl.conf exists
    if [ ! -f /etc/wsl.conf ]; then
        echo -e "+ ${CYAN}Creating new /etc/wsl.conf${NC}"
        cat > /etc/wsl.conf << EOF
[boot]
command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}
EOF
        echo -e "${GREEN}Configuration complete${NC}"
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
                    echo -e "+ ${CYAN}Checking configuration${NC}"
                    echo -e "${GREEN}Already configured correctly${NC}"
                    return 0
                else
                    # Some parameters are missing, attempt to update automatically
                    echo -e "+ ${CYAN}Checking configuration${NC}"
                    echo -e "${YELLOW}Missing parameters: ${MISSING_PARAMS}${NC}"

                    # Check if command is part of a chain
                    if echo "$CURRENT_COMMAND" | grep -q "&&\|;"; then
                        # Complex command, suggest manual update
                        echo -e "${YELLOW}!${NC} Manual update required for command chain"
                        echo -e "  ${CYAN}Current:${NC} $CURRENT_COMMAND"
                        echo -e "  ${CYAN}Add:${NC}${MISSING_PARAMS}"
                        return 1
                    else
                        # Simple command, update automatically
                        NEW_COMMAND="command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}"
                        sed -i "s|^command.*dockstart.*|$NEW_COMMAND|" /etc/wsl.conf
                        echo -e "${GREEN}✓${NC} Updated configuration"
                        return 0
                    fi
                fi
            else
                # dockstart not in command, check if we can append
                echo -e "${YELLOW}!${NC} Existing boot command found"

                # Check if command ends with semicolon
                if echo "$CURRENT_COMMAND" | grep -qE ';\s*$'; then
                    # Can append
                    NEW_COMMAND="${CURRENT_COMMAND} /usr/local/bin/dockstart ${REQUIRED_PARAMS}"
                    sed -i "s|^command.*|$NEW_COMMAND|" /etc/wsl.conf
                    echo -e "${GREEN}✓${NC} Appended to existing command"
                    return 0
                else
                    # Suggest manual update
                    echo -e "${YELLOW}!${NC} Manual update required"
                    echo -e "  ${CYAN}Add:${NC} ${CURRENT_COMMAND} && /usr/local/bin/dockstart ${REQUIRED_PARAMS}"
                    return 1
                fi
            fi
        else
            # Add command under existing [boot] section
            echo -e "${CYAN}▶${NC} Adding to existing [boot] section"
            sed -i "/^\[boot\]/a command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}" /etc/wsl.conf
            echo -e "${GREEN}✓${NC} Configuration complete"
            return 0
        fi
    else
        # Add [boot] section and command
        echo -e "${CYAN}▶${NC} Adding new [boot] section"
        cat >> /etc/wsl.conf << EOF

[boot]
command = /usr/local/bin/dockstart ${REQUIRED_PARAMS}
EOF
        echo -e "${GREEN}✓${NC} Configuration complete"
        return 0
    fi
}

# Configure for systemd
configure_systemd() {
    # Systemd configuration is handled in the main function

    # Required parameters for dockstart in systemd
    REQUIRED_PARAMS="--retry --force"

    # Check if service file already exists
    if [ -f /etc/systemd/system/dockstart.service ]; then
        echo -e "${CYAN}▶${NC} Checking existing service"

        # Check if the service file has the required parameters
        if grep -q "ExecStart=/usr/local/bin/dockstart" /etc/systemd/system/dockstart.service; then
            MISSING_PARAMS=""
            for param in $REQUIRED_PARAMS; do
                if ! grep -q -- "ExecStart=.*$param" /etc/systemd/system/dockstart.service; then
                    MISSING_PARAMS="$MISSING_PARAMS $param"
                fi
            done

            if [ -z "$MISSING_PARAMS" ]; then
                echo -e "${GREEN}✓${NC} Service already configured correctly"
            else
                echo -e "${YELLOW}!${NC} Missing parameters: ${MISSING_PARAMS}"

                # Update the ExecStart line
                sed -i "s|ExecStart=/usr/local/bin/dockstart.*|ExecStart=/usr/local/bin/dockstart ${REQUIRED_PARAMS}|" /etc/systemd/system/dockstart.service
                echo -e "${GREEN}✓${NC} Service updated"
                systemctl daemon-reload
            fi
        else
            echo -e "${YELLOW}!${NC} Service exists but not for dockstart"
            echo "$SYSTEMD_SERVICE_CONTENT" > /etc/systemd/system/dockstart.service
            echo -e "${GREEN}✓${NC} Service created"
            systemctl daemon-reload
        fi
    else
        # Create service file
        echo -e "${CYAN}▶${NC} Creating service file"
        echo "$SYSTEMD_SERVICE_CONTENT" > /etc/systemd/system/dockstart.service
        echo -e "${GREEN}✓${NC} Service created"
        systemctl daemon-reload
    fi

    # Enable service
    if systemctl is-enabled dockstart.service &>/dev/null; then
        echo -e "${GREEN}✓${NC} Service already enabled"
    else
        systemctl enable dockstart.service
        echo -e "${GREEN}✓${NC} Service enabled for boot"
    fi

    # Check if running
    if systemctl is-active dockstart.service &>/dev/null; then
        echo -e "${GREEN}✓${NC} Service already running"
    else
        # Offer to start
        read -p "Start service now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl start dockstart.service
            echo -e "${GREEN}✓${NC} Service started"
        fi
    fi

    return 0
}

# Main installation logic
if [ "$is_wsl" = true ]; then
    echo -e "+ ${CYAN}Checking configuration${NC}"
    configure_wsl
    wsl_result=$?

    if [ $wsl_result -eq 0 ]; then
        echo -e "${GREEN}Configuration complete${NC}"
    else
        echo -e "${YELLOW}Manual adjustment required (see above)${NC}"
    fi
else
    # Check if systemd is available
    if command -v systemctl >/dev/null 2>&1; then
        echo -e "+ ${CYAN}Configuring systemd service${NC}"
        configure_systemd
    else
        echo -e "${YELLOW}No auto-start system detected${NC}"
        echo -e "+ ${CYAN}Manual run: sudo /usr/local/bin/dockstart${NC}"
    fi
fi

print_header "SUMMARY"
echo -e "${GREEN}dockstart installed to /usr/local/bin/dockstart${NC}"
if [ "$is_wsl" = true ]; then
    echo -e "${YELLOW}Restart WSL to apply changes: wsl --shutdown${NC}"
fi

exit 0
