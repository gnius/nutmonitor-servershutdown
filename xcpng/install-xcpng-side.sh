#!/bin/bash
set -euo pipefail

USER=nutshutdown

# Create user
id -u $USER &>/dev/null || adduser --disabled-password --gecos "" $USER

mkdir -p /home/$USER/.ssh
chmod 700 /home/$USER/.ssh
chown -R $USER:$USER /home/$USER/.ssh

# Install scripts
install -m 755 ups-ssh-gate /usr/local/sbin/ups-ssh-gate
install -m 700 xcpng-ups-status-root /usr/local/sbin/xcpng-ups-status-root
install -m 700 xcpng-ups-shutdown-root /usr/local/sbin/xcpng-ups-shutdown-root

# Sudoers
cat <<EOF > /etc/sudoers.d/nutshutdown-ups
Defaults:$USER !requiretty
$USER ALL=(root) NOPASSWD: /usr/local/sbin/xcpng-ups-status-root, /usr/local/sbin/xcpng-ups-shutdown-root
EOF

chmod 440 /etc/sudoers.d/nutshutdown-ups

# SSH config
if ! grep -q "Match User $USER" /etc/ssh/sshd_config; then
cat <<EOF >> /etc/ssh/sshd_config

Match User $USER
    AuthenticationMethods publickey
    PasswordAuthentication no
    PermitTTY no
    X11Forwarding no
    AllowTcpForwarding no
    AllowAgentForwarding no
    ForceCommand /usr/local/sbin/ups-ssh-gate
EOF
fi

systemctl reload sshd

echo "Install complete. Add your public key to /home/$USER/.ssh/authorized_keys with 'restrict' prefix."
