# Installing the Framework from another machine

The install can be driven over ssh from a second machine instead of typed at
the laptop's own keyboard. That is worth the setup for one reason: when
something goes wrong, the output can be READ and kept rather than squinted at
on a console that may be scrolling, flooded, or showing a desktop that failed
to start.

This is how the VM testing was done, and every bug found there was found
because the output could be read from outside.

---

## The two stages, and why they are different

**Stage 1 — the machine as it is now.** Whatever it is running, ssh works or
can be made to work normally. Nothing here is special.

**Stage 2 — the Void live ISO.** This is the stage that matters, and the live
image has NO sshd running and knows none of your keys. Everything you set up
in stage 1 is gone the moment you boot the stick. The live environment has to
be bootstrapped by hand, once, at the laptop's keyboard.

---

## Stage 2: bootstrapping the live ISO

Boot the stick (**a rear bay — never front-right**, see `DEPLOY.md`), then type
these at the laptop. This is the only typing that has to happen there.

```sh
xbps-install -uy xbps      # the ISO is older than the repo and will refuse
                           # every transaction until it updates itself
xbps-install -Sy openssh
ssh-keygen -A              # the live image has NO host keys
passwd                     # a root password for this session only
ln -sfn /etc/sv/sshd /var/service/sshd
sv restart sshd            # RESTART, not `up` - see the note below
ip -4 -br addr             # read the address off the screen
```

### `sv restart`, not `sv up`

`sv up` is a no-op on a service that is already running, and sshd is often
already running — started before `ssh-keygen -A` created any host keys. **sshd
with no host keys accepts a connection and closes it immediately**, which the
client reports as

```
kex_exchange_identification: Connection closed by remote host
```

and which looks exactly like a firewall or network problem. This cost three
rounds of debugging in the VM before the pattern was clear. If ssh behaves that
way, the answer is almost always a restart.

---

## From the other machine

```sh
ssh root@<address>                 # the password just set
```

Then install:

```sh
xbps-install -Sy git
git clone https://github.com/jccl1706/void-qtile.git
cd void-qtile

./install/install_void.sh --preflight                      # touches nothing
./install/install_void.sh --dry-run --disk /dev/nvme0n1    # still touches nothing
```

**Read the dry run's partition names before going further.** They must be
`nvme0n1p1`, `nvme0n1p2`, `nvme0n1p3`. That branch has only ever been exercised
by `--dry-run`, which does not call `sfdisk`, and it is the one step that writes
to the disk.

Then the real thing:

```sh
./install/install_void.sh --disk /dev/nvme0n1 \
    --authorized-key /path/to/your.pub
```

### Run it detached

An install that is a child of the ssh session dies with the connection. That
happened once in testing: the log stopped mid-run and the machine came back at
a GRUB menu with no explanation.

```sh
nohup ./install/install_void.sh --disk /dev/nvme0n1 \
    --authorized-key key.pub > /root/install.log 2>&1 &
```

Then watch it from the other machine:

```sh
ssh root@<address> 'tail -5 /root/install.log'
```

### `--authorized-key` is not optional here

Pass the public key of the machine you are driving from. Without it the
installed system is reachable only by password at its own console — and if the
desktop fails to start, that console is a login loop. This is the difference
between diagnosing a problem over ssh and carrying the laptop to a desk.

---

## After the reboot

The LUKS passphrase must be typed at the laptop — dracut asks before any
network exists, and there is no way around that.

Once it is up, everything else can be checked from the other machine:

```sh
ssh jc@<address> '
  pgrep -f "qtile start" >/dev/null && echo "qtile running" || echo "qtile NOT running"
  ls /run/user/1000/wayland-0
  loginctl list-sessions
  getent hosts voidlinux.org >/dev/null && echo "dns ok"
'
```

If qtile is not running, the reason is in `~/.local/share/qtile/qtile.log` —
**not** in `~/.local/state/session.log`, which only ever shows repeated
headers, and not on the console. Every compositor failure found during testing
was found in that first file.

---

## What this setup cannot do

The LUKS passphrase at boot, and the first bootstrap of the live ISO. Both
happen before anything is listening, so both need somebody at the laptop.
Everything between them can be driven remotely.
