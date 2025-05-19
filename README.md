# Dockstart

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A lightweight command-line tool for Linux/WSL that automatically restores Docker containers with restart policies `always` or `unless-stopped` when the system or WSL starts.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/teomyth/dockstart/main/install.sh | sudo bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/teomyth/dockstart/main/install.sh | sudo bash
```

## Overview

Dockstart is designed to solve a common issue with Docker containers in WSL2 and Linux environments: **containers with restart policies don't automatically restart after a system reboot or WSL instance shutdown**.

### The Problem

Despite setting Docker containers with restart policies like `always` or `unless-stopped`, many users find that these containers don't automatically restart when:
- WSL2 is restarted
- The host Windows system is rebooted
- Docker Desktop is restarted

This is a [well-documented issue](https://forums.docker.com/t/docker-containers-in-wsl-2-wont-start-after-reboot/147552) affecting Docker Desktop with WSL2 integration. Even with proper restart policies configured, containers often remain stopped after system restart, requiring manual intervention.

### The Solution

Dockstart provides a simple solution by:
- Scanning all Docker containers
- Identifying those with restart policies set to `always` or `unless-stopped`
- Starting only the containers that match these criteria
- Running as a one-shot execution at system boot (not a daemon)

## Use Cases

- Developers running Docker inside WSL2
- Headless Linux servers running Docker containers
- Environments where Docker Desktop is not used or available
- Systems where you need containers to resume automatically after reboot

## Requirements

- Linux or WSL2 environment
- Docker installed and running
- `jq` for JSON parsing
- Root/sudo access for installation

## Installation

The quick install commands above will:
- Install the dockstart script to `/usr/local/bin/dockstart`
- Automatically detect if you're using WSL2 or standard Linux
- Configure the appropriate startup method for your environment
- Intelligently detect if it's being run through a pipe or locally

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/teomyth/dockstart.git
   cd dockstart
   ```

2. Run the installer:
   ```bash
   sudo ./install.sh
   ```

## How It Works

### In WSL2

The installer adds a `[boot]` command to `/etc/wsl.conf` that runs `dockstart` when WSL starts. The installer is smart enough to:

- Create a new `/etc/wsl.conf` file if it doesn't exist
- Add a `[boot]` section if it doesn't exist
- Add the command under an existing `[boot]` section
- Detect if dockstart is already configured and avoid duplicate entries
- Provide clear instructions if manual configuration is needed
- Configure dockstart with retry mode to wait for Docker to start

Example `/etc/wsl.conf` configuration:
```
[boot]
command = /usr/local/bin/dockstart --retry --force
```

The `--retry` option is important for WSL environments, as it allows dockstart to wait for Docker to initialize before attempting to start containers. This solves the common issue where Docker may not be immediately available when WSL starts. The retry mechanism is robust and will:

- Check if the Docker command exists, and wait for it to become available if it doesn't
- Check if the Docker service is running, and wait for it to start if it's not
- Check if the jq command is available, and wait for it to become available if it doesn't
- Retry at regular intervals until all dependencies are available or the maximum wait time is reached

This enhanced retry mechanism ensures that dockstart works reliably even in environments where Docker or its dependencies are not immediately available at boot time.

The `--force` option ensures that all containers with appropriate restart policies are started at boot time, even if they were manually stopped before the previous shutdown.

### In Linux with systemd

The installer creates a systemd oneshot service that runs after Docker starts. The service is enabled to run at system boot.

## Manual Usage

You can also run dockstart manually at any time:

```bash
sudo dockstart
```

### Command Line Options

Dockstart supports several command line options:

```bash
dockstart [OPTIONS]

Options:
  --retry              Enable retry mode for WSL boot (default: false)
  --retry-interval N   Seconds between retries (default: 10)
  --max-wait N         Maximum wait time in seconds (default: 600)
  --force              Force start all containers with restart policy, ignoring previous state
  --log-file PATH      Path to log file (default: /var/log/dockstart.log or ~/.dockstart.log)
  --no-log             Disable logging to file
  --log-max-size N     Maximum log file size in KB before overwriting (default: 1024)
  --version, -v        Show version information
  --help               Show this help message
```

The retry options are particularly useful in WSL environments where Docker may not be immediately available at boot time. When the `--retry` option is enabled, dockstart will check if Docker and its dependencies are available, and if not, it will wait and retry until they become available or the maximum wait time is reached.

The `--force` option ensures that all containers with restart policies `always` or `unless-stopped` are started, regardless of their previous state. This is particularly useful for containers with the `unless-stopped` policy that were manually stopped before a system shutdown.

## Troubleshooting

### WSL Configuration

If you need to restart WSL to apply changes:

```powershell
# From PowerShell
wsl --shutdown
```

### Checking Service Status (Linux)

```bash
systemctl status dockstart
```

### Logs

Dockstart maintains its own log file at `/var/log/dockstart.log` (or `~/.dockstart.log` if the system location is not writable). You can check these logs for detailed information about container startup:

```bash
# View dockstart's own logs
cat /var/log/dockstart.log

# Or if using the home directory fallback
cat ~/.dockstart.log
```

You can also check system logs for information about the dockstart service:

```bash
# In WSL
cat /var/log/syslog | grep dockstart

# In Linux with systemd
journalctl -u dockstart
```

To specify a custom log file location:

```bash
dockstart --log-file /path/to/custom/logfile.log
```

To disable logging to file:

```bash
dockstart --no-log
```

### Log Management

Dockstart includes a simple log management system to prevent log files from growing too large. By default, when the log file exceeds 1 MB (1024 KB), it will be overwritten with a new log file the next time dockstart runs.

You can customize the maximum log file size:

```bash
# Set maximum log file size to 5 MB (5120 KB)
dockstart --log-max-size 5120
```

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
