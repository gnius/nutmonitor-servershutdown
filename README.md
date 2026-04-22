# nutmonitor-servershutdown

## 🧠 Project Rationale

Traditional UPS shutdown approaches are designed for single machines. In a virtualization environment like XCP-ng, that model breaks down because:

- Multiple virtual machines must be shut down cleanly before the host
- The hypervisor should remain minimal and not run additional agents
- Granting external systems shell access introduces security risks

This project solves those problems by separating responsibilities:

- A lightweight external monitor (Docker container) makes decisions
- The hypervisor executes only tightly controlled, pre-approved actions

Key goals:

- Runtime-based shutdown decisions (not just "power lost")
- Graceful VM-first shutdown
- Strong security boundaries (no arbitrary command execution)

---

## 🧾 Solution Overview

### High-level summary

This system monitors a UPS via NUT and, when battery runtime drops below a defined threshold, triggers a controlled shutdown of an XCP-ng host and its virtual machines.

### Detailed flow

1. Container polls NUT (`upsc`)
2. Reads:
   - `ups.status` (OL / OB / LB)
   - `battery.runtime` (seconds remaining)
3. If:
   - UPS is on battery AND
   - runtime ≤ threshold
4. Then:
   - Send email notification (optional)
   - Execute restricted SSH command
5. XCP-ng host:
   - disables itself
   - shuts down VMs
   - shuts down host

---

## 🏗️ Architecture

```
UPS → NUT Server → Docker Monitor → (restricted SSH) → XCP-ng → VMs
```

---

## 🔐 Security Model

Security is a core design feature, not an afterthought.

### SSH restrictions

- key-based authentication only
- forced command (`ForceCommand`)
- `restrict` in authorized_keys
- no PTY
- no port forwarding
- no agent forwarding

### Privilege control

- dedicated user: `nutshutdown`
- no shell access
- `sudo` restricted to two exact scripts:
  - status
  - shutdown

### Result

Even if the container is compromised:

- it cannot run arbitrary commands
- it cannot obtain a shell
- it cannot escalate privileges beyond predefined actions

---

## ⚙️ Components

### Container

- polls NUT
- evaluates shutdown condition
- sends email notification
- triggers SSH command

### XCP-ng side

- SSH gate enforces allowed commands
- root scripts perform controlled operations

### Shutdown sequence

1. Disable host
2. Enumerate running resident VMs
3. Gracefully shut down VMs
4. Wait 60 seconds
5. Force shutdown remaining VMs
6. Shutdown host

---

## 📁 Repository Structure

- `Dockerfile`
- `docker-compose.yml`
- `monitor.sh`
- `.env.example`
- `xcpng/`
  - `ups-ssh-gate`
  - `xcpng-ups-status-root`
  - `xcpng-ups-shutdown-root`
  - `install-xcpng-side.sh`

---

## 🚀 Full Setup Instructions

### 1. Clone repository

```bash
git clone https://github.com/gnius/nutmonitor-servershutdown.git
cd nutmonitor-servershutdown
```

---

### 2. Generate SSH keys

```bash
mkdir -p secrets

ssh-keygen -t ed25519 -f secrets/id_ed25519 -N ""
ssh-keyscan -H <XCP-IP> > secrets/known_hosts

chmod 600 secrets/id_ed25519 secrets/known_hosts
```

---

### 3. Install on XCP-ng host

```bash
scp -r xcpng root@<XCP-IP>:/root/
ssh root@<XCP-IP>

cd /root/xcpng
chmod +x install-xcpng-side.sh
./install-xcpng-side.sh
```

---

### 4. Add SSH public key

```bash
nano /home/nutshutdown/.ssh/authorized_keys
```

Add:

```text
restrict ssh-ed25519 AAAA...yourkey...
```

---

### 5. Configure environment

```bash
cp .env.example .env
nano .env
```

Example:

```bash
NUT_UPS=myups@192.168.1.50:3493
XCP_HOST=192.168.1.20

RUNTIME_THRESHOLD_SECONDS=600
POLL_INTERVAL_SECONDS=30

SMTP_ENABLED=true
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user@example.com
SMTP_PASS=password
SMTP_FROM=user@example.com
SMTP_TO=alert@example.com
```

---

### 6. Run container

```bash
docker compose up -d --build
```

---

## 🧪 Testing

### Safe test

Set:

```bash
RUNTIME_THRESHOLD_SECONDS=999999
```

Then disconnect utility power.

Verify:

- Email sent
- SSH command executed
- Shutdown begins

---

## ⚠️ Notes

### XCP-ng pools

- Behavior differs in HA environments
- Test carefully before production use

### NUT accuracy

- `battery.runtime` depends on UPS quality
- Conservative thresholds are recommended

---

## 🔮 Future Improvements

- Multi-host orchestration
- Tiered shutdown policies
- Webhook notifications
- Health checks and retry logic

---

## 👍 Summary

This project provides a:

- Secure
- Predictable
- UPS-aware
- Virtualization-friendly

shutdown mechanism.

It cleanly separates decision-making from execution while maintaining strict control over system access.
