#!/usr/bin/env sh
# Run INSIDE the guest, from the live ISO:
#
#     curl -fsSL http://10.0.2.2:8000/vm-ssh.sh | sh
#
# Puts sshd and a throwaway key in place so the install can be driven from the
# host and its output read there, instead of being retyped into a VM window and
# relayed back by eye.
#
# NEEDED AFTER EVERY REINSTALL of the guest, because the disk is fresh each
# time - this configures the LIVE environment, which does not survive a reboot
# into the installed system.
set -eu

echo "==> installing openssh in the live environment"
xbps-install -Sy openssh >/dev/null 2>&1 || xbps-install -Sy openssh

mkdir -p /root/.ssh
chmod 700 /root/.ssh
curl -fsSL http://10.0.2.2:8000/vm-ssh-key.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# KEY ONLY. The live image's root password is public knowledge ("voidlinux")
# and this port is forwarded to the host's localhost, so password auth here
# would be an open door for anything else running on the host.
#
# APPENDED TO sshd_config DIRECTLY, not dropped into sshd_config.d. The drop-in
# directory only works if sshd_config carries an `Include` line for it, which
# is not guaranteed on a live image - and an earlier version of this script
# tried both with two heredocs sharing one tag on a single line, which is not
# valid shell and left sshd with a config it would not start on. Appending
# needs no Include and cannot half-apply.
#
# sshd takes the FIRST value of a keyword, so these lines must go at the TOP,
# not the bottom - anything already set further down would otherwise win.
cat > /tmp/sshd_config.new <<'SSHD'
PermitRootLogin prohibit-password
PasswordAuthentication no
SSHD
cat /etc/ssh/sshd_config >> /tmp/sshd_config.new
cp /tmp/sshd_config.new /etc/ssh/sshd_config

# Prove the config parses BEFORE trying to start on it: sshd -t says what is
# wrong, where a failed start says only that it failed.
echo "==> checking the sshd config"
sshd -t || { echo "sshd config is invalid - not starting"; exit 1; }

# Host keys, which a fresh live environment has none of - sshd exits
# immediately without them, and that is the likeliest reason a start appears to
# succeed and the port still refuses connections.
echo "==> generating host keys if absent"
ssh-keygen -A

echo "==> starting sshd under runit"
ln -sfn /etc/sv/sshd /var/service/sshd 2>/dev/null || true
sv up sshd 2>/dev/null || true
sleep 2

# If runit did not manage it, run sshd directly. -D would hold the terminal, so
# it is left to daemonise.
if ! ss -tln 2>/dev/null | grep -q ':22 '; then
    echo "==> runit did not bring it up; starting sshd directly"
    /usr/bin/sshd || /usr/sbin/sshd || true
    sleep 1
fi

echo "==> sshd listening:"
ss -tln 2>/dev/null | grep ':22 ' || {
    echo "    STILL NOT LISTENING. What to look at:"
    echo "      sv status sshd"
    echo "      sshd -t"
    echo "      sshd -D -ddd     (runs in the foreground and says why)"
}
echo
echo "==> from the host now:  ssh -p 2222 -i ~/.ssh/void-vmtest root@localhost"
