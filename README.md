# FireFlo releases

Built release artefacts for the FireFlo SMS Gateway, kept so that any version
ever handed to a customer can be recovered byte for byte and identified later.

FireFlo is commercial software, licensed per deployment, created and maintained
by [Remotiq](https://fireflo.au). Downloading a build from here grants no
licence to run it — see `LICENSE` inside the tarball. An unlicensed install
starts and carries traffic, but stops adopting configuration changes.

**New host?** Go straight to
[Install on a blank server](#install-on-a-blank-server) — every command from an
empty box to a running gateway, in order.

## Current

| | |
|---|---|
| **Version** | 0.9.23 |
| **File** | `fireflo-0.9.23-linux-x86_64.tar.gz` |
| **SHA-256** | `343571fc9404968eaf231071120f488ac9cb2194ecc242fe7c1da27671c46aa4` |
| **Built** | 2026-09-07, from gateway commit `badfdfb` |
| **Control panel** | 0.9.23.0, included at `panel/` |
| **REST panel** | 0.9.23.0, included at `rest-panel/` |
| **Platform** | linux-x86_64 — a native image, it will not run on another architecture |

Verify before installing. The checksum proves the download is intact; the
signature proves it came from us:

```
gpg --import SIGNING-KEY.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

**Check the key fingerprint rather than trusting the file beside the tarball.**
A signing key published in the same place as the thing it signs is only worth
as much as that place — anyone who could replace the tarball could replace the
key. `gpg --verify` must name:

```
3A9B 256F DE50 75CA 5F76  ADAF 42D7 A01A ED0D 03BA
FireFlo Releases <anshusah@hotmail.com>
```

If it names any other fingerprint, stop and ask us before installing.

0.9.0 is the first signed release. Builds before it carry a checksum only.

## Install on a blank server

The whole sequence, in order, for a host with nothing on it. Each step points at
the section or the page that explains it in full; this exists so it can be
followed top to bottom without deciding what to read next.

Roughly twenty minutes, most of it waiting for `apt`.

### Before you begin

Three of these decide whether the rest works, so they are worth reading rather
than discovering at step three.

| | Requirement |
|---|---|
| **Architecture** | **linux-x86_64.** The gateway is a native binary and will not run on ARM |
| **Operating system** | Ubuntu or Debian. Nothing else is handled by `setup.sh` |
| **Release** | Ubuntu focal, jammy, noble, plucky — Debian bullseye, bookworm, trixie |
| **PostgreSQL** | **14 or newer** |
| **Root** | Every step except `check` is run with `sudo` |

**Debian bullseye ships PostgreSQL 13 and is refused.** Add the
[PGDG repository](https://www.postgresql.org/download/linux/debian/) and upgrade
deliberately first. The refusal is on purpose: below 14 the schema migrations
fail partway, leaving a half-migrated database rather than a clean error.

**No Java is needed at any point.** The gateway carries its own runtime, and so
do the operator commands — `fireflo db migrate`, `fireflo license activate` and
the rest all run from the same executable. A JDK is only for building from
source.

**No RAM or CPU minimum is published.** Anything that comfortably runs
PostgreSQL is enough to install and evaluate; sizing for sustained high-rate
traffic depends on your message mix.

**Have your licence key to hand**, though not having it does not block the
install. An unlicensed gateway starts and carries traffic; what a missing
licence stops is picking up configuration changes.

### 1. Put the release on the host

```
scp fireflo-0.9.23-linux-x86_64.tar.gz SHA256SUMS SHA256SUMS.asc SIGNING-KEY.asc setup.sh root@newhost:/root/
```

### 2. Verify it before anything else

```
gpg --import SIGNING-KEY.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

**Read the fingerprint, not just "Good signature"** — it must be the one under
[Current](#current) above. The checksum only proves the file arrived whole;
anyone able to replace the tarball can replace the checksum beside it.

### 3. Prepare the host

```
sudo ./setup.sh --dry-run
sudo ./setup.sh
```

PostgreSQL, RabbitMQ and Node 22. See [Preparing a host](#preparing-a-host)
below for the flags and for what it deliberately leaves to you.

### 4. Create the database and role

Nothing does this for you. Installing a package is impersonal and reversible;
minting a credential is neither.

```
sudo -u postgres createuser --pwprompt fireflo
sudo -u postgres createdb --owner=fireflo fireflo
```

RabbitMQ keeps its default `guest` account, which the broker itself restricts to
loopback — the correct default, and the only one that needs no secret.

### 5. Unpack

```
tar xzf fireflo-0.9.23-linux-x86_64.tar.gz
cd fireflo-0.9.23-linux-x86_64
```

Read `MANIFEST`. It names the version, the commit and the platform this binary
was compiled for.

### 6. Install the gateway

Check first — it changes nothing.

```
./scripts/fireflo-install check
```

Three of its findings are worth understanding before you see them:

- **`psql` missing is fatal in database mode.** The operational tokens and the
  configuration rows are written with it. Without it the install runs the
  migrations and the bootstrap, then dies at the tokens — leaving a migrated,
  bootstrapped database behind a gateway that answers `404` on every `/ops`
  endpoint. `setup.sh` installs it.
- **A port already held is fatal on install** — 2775, 8080, 9000. A second
  instance given ports the first already holds completes, never binds, and then
  every check afterwards passes by answering from the *old* gateway.
- **`rsync` or `python3` missing are warnings only**, needed by `update` and by
  `fireflo send` and `verify` rather than by the install.

Put the database password in a file rather than on the command line — an
argument is a password in your shell history and in the output of `ps`.

```
umask 077 && printf '%s' 'THE-DB-PASSWORD' > /root/fireflo-db.pw

sudo ./scripts/fireflo-install install --from ./gateway \
    --config-source db --bootstrap \
    --db-name fireflo --db-user fireflo --db-password-file /root/fireflo-db.pw
```

It prints every decision before acting and waits. `--yes` skips the confirmation
for a scripted install; `--dry-run` shows the decisions without making them.

**`--bootstrap` writes the minimum a fresh database needs** — the default
routing table, one listener, one login. It refuses on a database that already
has rows, so it is only ever right on a new one. Coming from an existing
configuration, use `--import`.

Add `--smpp-port-range 2775-2799` if you expect more than one listener later: it
is the band the firewall opens and the band new listeners are allocated within,
so declaring it now covers every listener you will ever create. Add `--firewall`
to have the SMPP and HTTP ports opened for you, with OpenSSH allowed first.

### 7. Activate the licence

```
FIREFLO_LICENSE_KEY=your-key-here scripts/fireflo license activate
```

The key goes in the environment and never on the command line, so it stays out
of your shell history and out of `ps`.

### 8. Install the control panel

**After the gateway, not before** — the gateway owns the database schema and the
panel only reads and writes rows in it. Run it from the panel's own scripts
directory: it locates its source relative to itself, and there is no `--from`.

```
sudo ./panel/scripts/fireflo-panel-install install --gateway-conf-dir /etc/fireflo
```

That one flag gives it the ops URL, the metrics database and both operational
tokens.

### 9. Confirm it came up

```
cd /opt/fireflo && scripts/fireflo verify && systemctl is-active fireflo
```

`verify` exiting `4` on a brand-new install means the configuration is sound and
there is nothing to route to yet — expected before you add a vendor.

### Optional, once it is running

**Refused-login blocking.** Fill in `/etc/fireflo/fail2ban-ignore.conf` first: a
ban covers every port of the host, including SSH.

```
sudo ./scripts/fireflo-install fail2ban --fail2ban-ignore "YOUR.OFFICE.IP,YOUR.MONITOR.IP"
```

**A durable queue.** Without a broker the queue is in memory and a restart drops
whatever has not reached a vendor. Pass
`--broker-uri amqp://guest:guest@127.0.0.1:5672/%2F` to use the RabbitMQ
`setup.sh` installed.

**The customer-facing REST panel** is optional and installs the same way from
`rest-panel/scripts/`. It needs its **own** database — never the gateway's,
whose schema is version-checked and would meet tables it does not know about.

### When the next release arrives

Verify it, unpack it, and:

```
sudo ./scripts/fireflo-install update --from ./gateway
```

`update` never touches your configuration directory, and keeps the previous
version so `fireflo-install rollback` is one command. The panel is upgraded
separately by its own installer.

## Preparing a host

`setup.sh` installs the services FireFlo talks to, on Ubuntu and Debian. It
exists because the gateway's own installer does not: `fireflo-install` adds the
PostgreSQL **client** and no server, and never mentions a broker — so between
unpacking the tarball and running the installer there is a step that was only
ever written down in prose.

```
sudo ./setup.sh --dry-run     # read what it would do first
sudo ./setup.sh
```

It installs PostgreSQL (14 or newer), RabbitMQ, and Node 22 for the control
panel. Java is **not** installed unless you pass `--with-java`: this gateway is
a native binary and opens no JDK, so a JDK is only wanted for building from
source.

**It creates no database, no role and no password**, and no RabbitMQ user or
vhost. Installing a package is impersonal and reversible; minting a credential
and writing it to disk is neither, and it is not a decision a setup script
should take for you. It prints the commands to run instead.

**`setup.sh` is not signed**, unlike the release tarball — it is a plain script
in this repository rather than a build artefact. It is one readable file with no
network fetch except the NodeSource and Adoptium installers it names, so read it
before you run it as root.

## Removing an install

`cleanup.sh` removes a FireFlo install from a host — the systemd units, the
application directory and the configuration directory.

```
sudo ./cleanup.sh --list                    # what is on this host
sudo ./cleanup.sh --tenant acme --dry-run   # read what it would do first
sudo ./cleanup.sh --tenant acme
```

It reads every path out of the systemd unit rather than deriving it from a
naming convention, because an install that was relocated keeps its real paths
there and nowhere else. With more than one install on the host it refuses to act
without `--tenant` or `--service`, rather than guessing.

**It keeps your data.** The data and log directories survive unless you pass
`--purge-data` or `--purge-logs`, and it never drops a database or a role — a
CDR history outlives the software that wrote it. It also leaves PostgreSQL,
RabbitMQ and Node alone, because `setup.sh` installs those host-wide and a
second tenant is probably still using them.

**Release the licence in your account before running it, not after.** A licence
still bound to a host that no longer exists has to wait out the tolerance window
before another machine can take it.

## Earlier builds

**Only the current release is published here.** Builds before 0.9.23 have been
withdrawn and their tarballs removed from this tree.

**0.9.22 is different from the retirements above it, and worth reading before you
skip this paragraph.** Those were retired on capability — installs running them
were fine. 0.9.22's headline feature did not work:

- **its blocking could not be switched on at all** on a gateway that already
  existed, which is every gateway that was updated rather than freshly installed;
- **`--dry-run` wrote to the host** in that step, so a run meant to preview
  changes made them;
- **a reboot did not release a ban**, and a ban covers every port — so a mistake
  that locked you out of your own SSH stayed locked after a restart.

**If you took 0.9.22 for the blocking, take 0.9.23.** If you took it for the
`X-Forwarded-For` fix, you already have that and this is not urgent.

**0.9.23 makes it work.** `fireflo-install fail2ban` turns blocking on for an
install that already exists, without reinstalling; `--dry-run` writes nothing;
and a boot-time unit releases FireFlo's bans while leaving the host's own `sshd`
and `postfix` jails alone.

**Bans cover every port of the host, deliberately** — somebody working through
SMPP passwords has no business anywhere on the box. The cost is that a false
positive costs that address everything, so
**fill in `/etc/fireflo/fail2ban-ignore.conf` before you enable a jail**, and know
where your provider's console is. Changes to that file apply on the next attempt
with no reload, which is what you want when you are undoing a lockout.

**0.9.22 recorded every refused login, showed them, and could block the address.**
A refused SMPP bind, a refused API password and a refused panel sign-in now each
write one line to a log of their own; a new Security page in the control panel
shows all of them beside whoever fail2ban is currently blocking; and
`fireflo-install --with-fail2ban` ships the jails that do the blocking — **off by
default**, because it edits host security configuration and grants the panel one
narrow sudo rule.

**It carries a security fix worth taking on its own.** With proxy forwarding
enabled, the REST API read the **left-most** `X-Forwarded-For` entry. The common
nginx recipe appends rather than overwrites, so that entry is whatever the client
sent — meaning a credential's allowed-addresses list could be satisfied with a
forged header. It now counts from the right under `smsg.restapi.proxy.hops`
(default 1) and otherwise uses the socket address, which cannot be forged. An
estate behind a single proxy needs no change; behind a CDN and a proxy, set the
key to 2.

**One new log file**, `auth-failed.log`, on by default and empty unless somebody
is failing to log in. It is deliberately not governed by `QUARKUS_LOG_FILE_ENABLE`
— a gateway with file logging off would otherwise record nothing and leave jails
that look configured and protect nothing.

**Nothing blocks anybody until you pass `--with-fail2ban`**, and before you do,
fill in `/etc/fireflo/fail2ban-ignore.conf`: a ban is on an address, and an
address usually carries a whole customer.

**0.9.21 made Stop sending and Hold act on a listener's own traffic.** On every
earlier build both controls paused only the delivery receipts going back to
bound customers: a listener you had told to stop kept accepting submits and kept
sending them out. **Upgrade if you rely on either control on a listener.** After
this release, Stop sending accepts and parks — the message is charged, held
un-routed, and delivered once when you resume, with receipts flowing throughout
— while Hold refuses at the door with `ESME_RMSGQFUL` before any charge is
taken. On a vendor, Stop sending now also stops its retries, and the Hold toggle
is replaced by a **Restart** that re-dials the connection. Nothing else changes:
no migration, no new configuration keys, and a vendor carrying a `pause`
property is still honoured.

**0.9.20 was the performance release.** The audited fix set (0.9.17) plus the
receipt-store rework (0.9.19-0.9.20): the ten-minute 3,000 msg/s sustained run
now holds flat with a p99 under 20 ms and a receipt store a third of its former
size, refused SMPP binds are counted by reason on the metrics endpoint, and the
postpaid credit poll is an order of magnitude lighter. **One default moved**:
`smsg.dlr.correlation.days` is now `2` (was `3`); an estate that set the key
explicitly is untouched. **Do not downgrade past 0.9.19 with a live receipt
store** — the store format gained a value-stamp form older builds cannot read.

**Do not install 0.9.2 if you still have it.** It bundled the control panel
for the first time but placed the panel's installer where it cannot find the
panel source, so installing the panel from that tarball fails with a message
about the checkout not looking like the control panel. 0.9.3 is that fix; the
gateway half of 0.9.2 was sound.

**BOTH PANELS ARE INCLUDED**, as they have been since 0.9.11. The operator's
control panel is at `panel/` and the customer-facing REST panel at `rest-panel/`,
each as source with its own installer inside its own tree. Neither is required:
the gateway installs and runs without them.

They are paired by version — a panel's first three numbers name the gateway
release it was built against — and both in this tarball are **0.9.23.0**, so they
match the gateway beside them. **The control panel is worth upgrading with this
gateway**: it is what carries the corrected traffic controls, the parked count on
a suspended listener, and the vendor Restart button. A panel you already have is **not** touched by
upgrading the gateway from here; it is upgraded by its own installer.

**0.9.8 corrected what the registration endpoints report**, and that is worth
upgrading for. 0.9.7 added customer-facing registration — a caller holding
ordinary gateway credentials can ask for a sender ID or a message template over
`/secure/senders` and `/secure/templates`, and what they write is stored
**awaiting approval and is not enforced**.

But a registration an operator had **withdrawn** still reported itself as
`APPROVED` over that API, while the gateway refused its traffic. A customer
asking "can I send from this" was told yes and then refused. From 0.9.8 the API
reports a fourth state, `WITHDRAWN`, and only `APPROVED` means usable.

**Upgrade from 0.9.7 if you have enabled those endpoints for anyone.** If nobody
is calling them the correction is inert, and 0.9.7 is otherwise sound.

**0.9.11 carries NO database migration**, and nor did 0.9.10, 0.9.9, 0.9.8 or 0.9.7. From 0.9.6
onwards this is a binary swap and nothing else.

Coming from **0.9.5 or earlier you still owe `V1.47.0`**, which arrived in 0.9.6
and adds `cdr_submit.route_rule`; from **0.9.1 or earlier you also owe
`V1.46.0`**, which arrived in 0.9.3. Both columns are additive and nothing reads
them back to make a decision, so the migrations are quick and a rollback to the
previous binary keeps working against the migrated schema.
`fireflo-install update` handles them.

- **Never install 0.8.6.** It rejects every licence this server issues, and the
  symptom reads as a licensing fault rather than as a broken build.
- **0.8.7 and 0.8.8 work.** If you are running one, upgrade when convenient —
  neither is dangerous, and neither needs an emergency change. 0.8.7 grants
  itself a resettable trial window; 0.8.8 cannot release a licence, so a machine
  cannot be transferred without waiting out the tolerance window.

If you need to identify a build you already hold, read its key with the command
below and ask us — we keep the record even though the file is no longer offered.

## Which signing key a build trusts

Each gateway binary has one Ed25519 public key compiled into it and accepts
licences signed only by the matching private key. That key is not configurable
at runtime, by design — an install that could be told which key to trust could
be told to trust a key its holder generated.

So the question "will this build accept our licences?" is answered by reading
the key out of the binary:

```
strings -a gateway/fireflo-gateway | grep -o 'MCowBQYDK2VwAyEA[A-Za-z0-9+/=]*'
```

0.9.23 answers `MCowBQYDK2VwAyEA7cEZKZae5xBb8uwIgvCmxBzW7ceOKl0YiFE1AburdAI=`, and
that is the only key in it — unchanged since 0.8.9, so an install upgrading from
any of those needs no new licence. That is a public value; publishing it is safe and is
what makes a build identifiable. A mismatch here presents as licences being
rejected as MALFORMED, which reads like a fault in the licence server rather
than in the binary — the reason it is worth checking directly.

## What is not here

The private signing key is **not in this repository and must never be**, in any
form, in any commit, including history. See `.gitignore`.

**Both panels are in this tarball**, at `panel/` and `rest-panel/`. Neither is
needed to install or run the gateway, and neither is touched by upgrading the
gateway — each is installed and upgraded by its own installer, which lives inside
its own directory here.
