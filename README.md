# nutmonitor-servershutdown

A small Docker-based NUT client that monitors a UPS, calculates remaining battery runtime, sends an email notification when shutdown is triggered, and cleanly shuts down an XCP-ng host through a tightly restricted SSH account.

## What it does

- Polls a NUT server with `upsc`
- Watches `ups.status` and `battery.runtime`
- Triggers shutdown when the UPS is on battery and runtime is less than or equal to a configured threshold
- Sends an email notification when the shutdown command is issued
- Connects to XCP-ng over SSH using a dedicated account that cannot obtain an interactive shell
- Runs only two privileged operations on XCP-ng through fixed root-owned wrappers:
  - `status`
  - `shutdown`
- Shuts down running resident VMs before shutting down the XCP-ng host

## Security model

The container does **not** get a general shell on the XCP-ng host.

- SSH key authentication only
- `ForceCommand` on the XCP-ng side
- `restrict` option in `authorized_keys`
- no PTY, no forwarding, no agent, no X11
- `sudo` limited to two exact root-owned scripts

This keeps the container from being able to run arbitrary commands on the virtualization server.

## Repository layout

- `Dockerfile` - container image
- `docker-compose.yml` - example deployment
- `monitor.sh` - main polling and decision logic
- `xcpng/ups-ssh-gate` - forced SSH gate on XCP-ng
- `xcpng/xcpng-ups-status-root` - minimal status wrapper
- `xcpng/xcpng-ups-shutdown-root` - VM shutdown loop and host shutdown wrapper
- `xcpng/install-xcpng-side.sh` - helper installer for the XCP-ng side
- `.env.example` - example environment configuration

## Container behavior

The monitor loop:

1. Reads `ups.status`
2. Reads `battery.runtime`
3. If power is restored (`OL`), it clears its shutdown latch
4. If on battery (`OB` or `LB`) and runtime is less than or equal to the configured threshold, it:
   - sends an email notification if SMTP is configured
   - calls the restricted SSH `shutdown` command
   - latches to avoid repeated shutdown requests

## XCP-ng behavior

The shutdown wrapper:

1. Disables the host
2. Enumerates running resident VMs that are not the control domain
3. Attempts graceful shutdown for each VM
4. Waits for a configurable grace period
5. Force shuts down any remaining running resident VMs
6. Calls `xe host-shutdown`

## Quick start

### 1. Create SSH key material on the Docker host

```bash
mkdir -p secrets
ssh-keygen -t ed25519 -f secrets/id_ed25519 -N ""
ssh-keyscan -H 192.168.1.20 > secrets/known_hosts
chmod 600 secrets/id_ed25519 secrets/known_hosts
```

### 2. Install the XCP-ng side scripts

Copy the files in `xcpng/` to the XCP-ng host and run:

```bash
chmod +x install-xcpng-side.sh
./install-xcpng-side.sh
```

Then add the public key from `secrets/id_ed25519.pub` to `/home/nutshutdown/.ssh/authorized_keys` using the `restrict` prefix.

Example:

```text
restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...yourkey...
```

### 3. Configure the container

Copy `.env.example` to `.env` and edit the values.

### 4. Start the service

```bash
docker compose up -d --build
```

## Required NUT variables

This project expects the NUT server to expose:

- `ups.status`
- `battery.runtime`

## Email notifications

Email sending is optional. If SMTP settings are provided, the container uses `msmtp` to send an email when shutdown is triggered.

## Notes for XCP-ng pools

The current wrapper is designed to safely shut down resident VMs and then the host itself. In a pool, shutdown of a pool master and HA-enabled environments should be planned carefully because host shutdown behavior depends on pool role and HA state.

## References

- XCP-ng general shutdown flow: disable host, migrate or shut down VMs, then shut down host.
- `xe host-shutdown` requires the host to be disabled first.
- NUT exposes `battery.runtime` in seconds and `ups.status` state flags.
- OpenSSH supports `restrict` and forced commands in `authorized_keys` / `sshd` policy.
