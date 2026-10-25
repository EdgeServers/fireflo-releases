# FireFlo releases

Built release artefacts for the FireFlo SMS Gateway, kept so that any version
ever handed to a customer can be recovered byte for byte and identified later.

FireFlo is commercial software, licensed per deployment, created and maintained
by [Remotiq](https://fireflo.au). Downloading a build from here grants no
licence to run it — see `LICENSE` inside the tarball. An unlicensed install
starts and carries traffic, but stops adopting configuration changes.

**New host?** Go straight to
[Install on a blank server](#install-on-a-blank-server) — every command from an
empty box to a running gateway, in order. **Want a durable queue?**
[Install and configure Kafka](#install-and-configure-kafka) — one command, on a
new box or one already running.

## Current

| | |
|---|---|
| **Version** | 0.14.0, with control panel 0.14.0.0 — **breaking: RabbitMQ is removed** (the queue is in memory, the default, or Kafka; an install still on RabbitMQ must be drained first, see [Upgrading from 0.13.x](#upgrading-from-013x)); optional Kafka backbone, which is also cluster mode: several gateway nodes on one PostgreSQL and one Kafka; a message no routing rule matches is refused at once instead of accepted and refunded; copy routes are unbilled and silent; `setup.sh` gains host roles, a broker choice (Redpanda or Apache Kafka) and RHEL-family 9+ hosts; schema 1.109.0, upgrading is a maintenance window (see [the 0.14.0 notes](#earlier-builds)). Before it: 0.13.5 billing and receipt fixes (a long message refunded once, late receipts delivered, every part's receipt counted); 0.13.4.4 stats pages that no longer time out; 0.13.4 and 0.13.3 native management port fixes; 0.13.2 session rows and per-account listener view; 0.13.1 `health.currency`; and from 0.13.0, **breaking**: the management port is GraphQL-only (`/ops` is gone), guarded by an address allow-list, with metrics on the main port, the platform API for OMNI, the slow query log and refusals by listener with fail2ban bans (see [the 0.13.0 notes](#earlier-builds)) |
| **File** | `fireflo-0.14.0-linux-x86_64.tar.gz` |
| **SHA-256** | `7100428a43efad1bb673312a1bdd172c201c1aba62167f3f8669e793f703c5db` |
| **Built** | 2026-10-24, from gateway commit `036a71f` with control panel `v0.14.0.0`, see [the 0.14.0 notes](#earlier-builds) |
| **Control panel** | 0.14.0.0, included at `panel/`, from commit `8d83df4` (tag `v0.14.0.0`) |
| **SMPPSim** | included at `smppsim/` — third-party test SMSC, GPL-2, its licence and source beside it; installed only with `--with-smppsim` |
| **REST panel** | not included — unchanged at 0.11.0.0, see [the 0.11.3 notes](#earlier-builds) |
| **Platform** | linux-x86_64 — a native image, it will not run on another architecture |
| **ARM (aarch64)** | `fireflo-0.14.0-linux-jvm.tar.gz`, SHA-256 `af488a4ca1546734571e83fe475e088d3f7e464c4b6905865155895b40ff1baf`, checksummed in `SHA256SUMS-jvm` — the same release with the Java build of the gateway. Needs Java 25 installed first; see [ARM servers](#arm-servers-the-java-build) |

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

## ARM servers: the Java build

The native gateway is compiled for x86-64; on an ARM server it fails at once with
`Exec format error`. `fireflo-0.14.0-linux-jvm.tar.gz` is the same release —
control panel, SMPPSim, scripts — with the **Java build** of the gateway in
`gateway/`, which runs on any 64-bit Linux.

**Install Java 25 before anything else.** The installer's own checks already run
the gateway's commands, so Java must be there before `fireflo-install check`:

```
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo tee /etc/apt/keyrings/adoptium.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release; echo $VERSION_CODENAME) main" | sudo tee /etc/apt/sources.list.d/adoptium.list
sudo apt-get update && sudo apt-get install -y temurin-25-jdk
```

That is for Ubuntu and Debian. On a RHEL-family host, or on either if you would
rather not type it, `sudo ./setup.sh --with-java` adds the same Temurin 25 from
Adoptium's own apt or rpm repository.

Then verify it the same way, against its own checksum file:

```
gpg --verify SHA256SUMS-jvm.asc SHA256SUMS-jvm
sha256sum -c SHA256SUMS-jvm
tar xzf fireflo-0.14.0-linux-jvm.tar.gz && cd fireflo-0.14.0-linux-jvm
```

and follow [Install on a blank server](#install-on-a-blank-server) from step 3
with every command unchanged: `--from ./gateway` finds the Java build, and the
unit runs it with `java -jar`. Expect a start of a few seconds rather than a
fraction of one, and 1–2 GB more memory than the native build. Only the optional
Brotli response compression is x86-only; on ARM responses fall back to gzip.

## Install on a blank server

The whole sequence, in order, for a host with nothing on it. Each step points at
the section or the page that explains it in full; this exists so it can be
followed top to bottom without deciding what to read next.

Roughly twenty minutes, most of it waiting for the package manager. The commands
below are for one box carrying everything — the right shape for most
deployments; splitting it across hosts is
[Multi-host and clustering](#multi-host-and-clustering).

### Before you begin

Three of these decide whether the rest works, so they are worth reading rather
than discovering at step three.

| | Requirement |
|---|---|
| **Architecture** | **linux-x86_64** for the native release. On ARM (aarch64, e.g. AWS Graviton) use the Java build instead — see [ARM servers](#arm-servers-the-java-build) |
| **Operating system** | Ubuntu or Debian (`apt`), or RHEL-family 9 or newer — RHEL 9, CentOS Stream 9, Rocky Linux 9, AlmaLinux 9 (`dnf`). `setup.sh` refuses anything else, naming what `/etc/os-release` said |
| **Release** | Ubuntu focal, jammy, noble, plucky — Debian bullseye, bookworm, trixie — on RHEL-family hosts, 9 and newer |
| **PostgreSQL** | **14 or newer** |
| **Root** | Every step except `check` is run with `sudo` |

**Debian bullseye ships PostgreSQL 13 and is refused.** Add the
[PGDG repository](https://www.postgresql.org/download/linux/debian/) and upgrade
deliberately first. The refusal is on purpose: below 14 the schema migrations
fail partway, leaving a half-migrated database rather than a clean error.

**No Java is needed at any point.** The gateway carries its own runtime, and so
do the operator commands — `fireflo db migrate`, `fireflo license activate` and
the rest all run from the same executable. A JDK is only for building from
source. The optional SMPPSim test SMSC is the one exception: choosing it adds
the distribution's Java runtime, for SMPPSim alone.

**No RAM or CPU minimum is published.** Anything that comfortably runs
PostgreSQL is enough to install and evaluate; sizing for sustained high-rate
traffic depends on your message mix.

**Have your licence key to hand**, though not having it does not block the
install. An unlicensed gateway starts and carries traffic; what a missing
licence stops is picking up configuration changes.

### 1. Put the release on the host

```
scp fireflo-0.14.0-linux-x86_64.tar.gz SHA256SUMS SHA256SUMS.asc SIGNING-KEY.asc setup.sh root@newhost:/root/
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

PostgreSQL, a single-node Redpanda broker on loopback, and Node 22 — the
default `--role all`. See [Preparing a host](#preparing-a-host) below for the
roles, the broker choice and what it deliberately leaves to you.

### 4. Create the database and role

Nothing does this for you. Installing a package is impersonal and reversible;
minting a credential is neither.

```
sudo -u postgres createuser --pwprompt fireflo
sudo -u postgres createdb --owner=fireflo fireflo
```

The broker gets no user either. On one box it listens on loopback only, so it
needs none; on a broker host of its own, firewall 9092 to the gateway subnet
before anything else (the summary `setup.sh` prints has the lines).

### 5. Unpack

```
tar xzf fireflo-0.14.0-linux-x86_64.tar.gz
cd fireflo-0.14.0-linux-x86_64
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
  bootstrapped database behind a gateway the control panel cannot manage.
  `setup.sh` installs it.
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

**To see a message go all the way through first**, add `--with-smppsim` (and
`--balance` to try prepaid). It installs SMPPSim, the test SMSC in `smppsim/`,
as its own service, routes `MESSAGE` to it, asks for a cost on it and opening
credit for the first account, and ends by running `fireflo selftest`: one real
message, checked as routed, priced, delivered and debited. Run the self-test
again whenever you like. SMPPSim accepts everything and invents its delivery
receipts — replace it with a real vendor before real traffic. Its ports, 7775
and 7788, are never opened; it listens on every interface, so keep a firewall
in front of them.

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
whatever has not reached a vendor — the default, and a real trade rather than
an oversight. To use the broker `setup.sh` installed, give the install
`--kafka-bootstrap 127.0.0.1:9092 --node-id gw-1` (or, on an install that
already runs, `fireflo-install update --from ./gateway --kafka-bootstrap
127.0.0.1:9092 --node-id gw-1 --migrate`). A message is then acknowledged to the
customer only once the broker has it, and if the broker is down the gateway
refuses new messages (SMPP `ESME_RMSGQFUL`, HTTP `503`) rather than falling back
to memory. The gateway creates its topics when it starts; `fireflo broker init`
creates them ahead of time if your broker does not let clients do that. Every
form of this — one box, an install already running, a broker on its own host —
is in [Install and configure Kafka](#install-and-configure-kafka).

**The customer-facing REST panel** is optional and installs the same way from
`rest-panel/scripts/`. **0.14.0 does not carry it**: take it from the 0.11.0
tarball (commit `42d506e` of this repository), where it is 0.11.0.0 and
unchanged since. It needs its **own** database — never the gateway's,
whose schema is version-checked and would meet tables it does not know about.

### When the next release arrives

Verify it, unpack it, and:

```
sudo ./scripts/fireflo-install update --from ./gateway
```

`update` never touches your configuration directory, and keeps the previous
version so `fireflo-install rollback` is one command. The panel is upgraded
separately by its own installer.

On a Kafka install `update` needs to be told which node migrates: `--migrate`
on the first, `--no-migrate` on every other, after `fireflo-install service
stop` on all of them. **Coming from 0.13.x**, read
[Upgrading from 0.13.x](#upgrading-from-013x) first.

### Multi-host and clustering

From 0.14 the database, the broker, the gateway nodes and the control panel can
each be a machine of their own, and the gateway can be two or more nodes behind
a TCP load balancer. Run `setup.sh` once per host with that host's role —
`db`, `broker`, `gateway`, `panel` — and it ends by printing the install
command and the firewall lines for that role:

```
sudo ./setup.sh --role db --allow-from 10.0.0.0/24      # PostgreSQL, reachable from the gateways
sudo ./setup.sh --role broker                           # one Redpanda node, or one of three with --ips
sudo ./setup.sh --role gateway                          # client tools only
sudo ./setup.sh --role panel                            # Node 22 and a PostgreSQL client
```

A cluster is what `--kafka-bootstrap` makes: every node shares one PostgreSQL
and one Kafka and has its own `--node-id`. The first node installs with
`--role gateway --bootstrap`; every further node with `--role gateway --join
--no-migrate --secrets-key-file <file>`, where the file holds the first node's
`FIREFLO_SECRETS_KEY` — without the same key a node cannot read the customer
passwords the first one sealed. Each vendor is held by one node at a time and
moves to another if that node dies; receipts reach the node holding the
customer's bind; credit and rate limits are shared out between nodes. A panel on
its own host is installed with `--gateway-ops-url`, `--gateway-base-url`, the
database flags with `--db-password-file`, the token files, and optionally
`--gateway-ops-urls gw-1=…,gw-2=…` to fail over between nodes;
`fireflo-panel-install --help` lists them.

The full guide — sizing, load balancer, failover, upgrading a cluster — is
[Clustering](https://docs.fireflo.au/platform/install/clustering) in the
documentation.

## Upgrading from 0.13.x

**Plan a maintenance window.** 0.14.0's migrations (schema 1.109.0; V1.105.0
moves held credit to a per-node owner) need every gateway on the database
stopped while they run. On one host `fireflo-install update` does that itself.
With several nodes: `fireflo-install service stop` on each, then `update
--migrate` on the first and `update --no-migrate` on the rest — the installer
refuses the wrong order rather than trusting it. Credit held under the old
host-name owner carries over.

**RabbitMQ is gone.** An install whose stored `smsg.queue.provider` is
`rabbitmq` will not start on 0.14, so `update` checks for it before stopping
anything and refuses, printing this procedure:

1. Stop customer intake — the load balancer, or the listeners.
2. Wait until `fireflo health` shows the broker queue and the router queue
   both at 0, so nothing is left in RabbitMQ.
3. Update with where the queue goes now: `update --from ./gateway --no-broker`
   for the in-memory queue, or `--kafka-bootstrap host:9092 --node-id gw-1
   --migrate` for Kafka.

`--broker-uri` and `--broker-queue` are refused, naming the replacement.
RabbitMQ itself is left installed; remove it when you are done with it.

## Install and configure Kafka

Without a broker the gateway queues in memory, and a restart drops whatever has
not reached a vendor. With Kafka a message is acknowledged only once the broker
has it — and Kafka is also cluster mode, so a second gateway node is an install
rather than a migration ([Clustering](https://docs.fireflo.au/platform/install/clustering)
in the documentation). This section is the commands.

`setup.sh --configure-gateway` does it in one run: it installs Apache Kafka (or
finds it installed), waits until the broker answers, then runs the gateway's
own `fireflo-install` with `--kafka-bootstrap` — `install` where there is no
gateway yet, `update` where there is one. It finds the release you unpacked
beside it (or take `--gateway-dir DIR`) and never unpacks or verifies a tarball
itself. Anything after a lone `--` goes to `fireflo-install` unchanged.
`sudo ./setup.sh --help` covers every flag; `--dry-run` prints the whole plan,
the `fireflo-install` line included, and changes nothing.

### One box from scratch

Gateway, database and Kafka on one host — the [blank server](#install-on-a-blank-server)
sequence with Kafka in place of Redpanda. Prepare the host, create the database
role, then let the same command point a new gateway at the broker:

```
sudo ./setup.sh --role all --broker kafka --with-java

sudo -u postgres createuser --pwprompt fireflo
sudo -u postgres createdb --owner=fireflo fireflo
umask 077 && printf '%s' 'THE-DB-PASSWORD' > /root/fireflo-db.pw

tar xzf fireflo-0.14.0-linux-x86_64.tar.gz      # after verifying it
sudo ./setup.sh --role all --broker kafka --configure-gateway -- \
    --config-source db --bootstrap \
    --db-name fireflo --db-user fireflo --db-password-file /root/fireflo-db.pw
```

The second run leaves what the first installed alone. Kafka listens on
127.0.0.1:9092 only, and the gateway becomes node `gw-1` (`--node-id` to name
it otherwise). `--with-java` is only for a host with no Java 17 or newer: Kafka
is a JVM, the gateway is not. Carry on from
[step 7](#7-activate-the-licence).

### An install that already runs on the in-memory queue

Switching restarts the gateway, and what is queued in memory when it stops is
lost. So drain it first, then switch:

1. Stop customer intake — suspend the listeners or take the node out of the
   load balancer, and pause anything that submits over HTTP.
2. Wait until `sudo /opt/fireflo/bin/fireflo health` shows `router_queue` at 0
   and every worker's `queue_depth` and `retry_queue_depth` at 0.
3. Then, from beside the unpacked release:

```
sudo ./setup.sh --role all --broker kafka --configure-gateway --yes-drained
```

`--yes-drained` is required while the gateway runs, and is checked rather than
trusted: `setup.sh` reads `fireflo health` before installing anything and again
just before the switch, and refuses while anything is queued. The update keeps
the node's existing id, needs the install to have a database (Kafka mode keeps
receipt correlation in PostgreSQL — receipts still awaited are imported from
the old store on the first start), and, if the release beside it is newer than
the running gateway, upgrades it in the same step; the plan it prints says so.
Reopen intake afterwards. A tenant install is named with
`--gateway-conf-dir /srv/fireflo/acme/gateway/conf`.

The same by hand, two steps — drained the same way first, since nothing checks
it for you on this path:

```
sudo ./setup.sh --role all --broker kafka
cd fireflo-0.14.0-linux-x86_64
sudo ./scripts/fireflo-install update --from ./gateway --kafka-bootstrap 127.0.0.1:9092 --migrate
```

### Kafka on its own host

On the broker host, with the address the gateways reach it on:

```
sudo ./setup.sh --role broker --broker kafka --advertise-ip 10.0.0.20 --with-java
```

It binds 9092 on every interface and advertises `10.0.0.20:9092`, PLAINTEXT
with no ACLs — so **firewall 9092 to the gateway subnet before anything else**
(the summary prints the `ufw` or `firewall-cmd` lines). Its controller port,
9093, is loopback-only.

Then on each gateway host, its own `--node-id` each time:

```
sudo ./setup.sh --role gateway --configure-gateway --kafka-bootstrap 10.0.0.20:9092 --node-id gw-1 -- \
    --config-source db --bootstrap \
    --db-host 10.0.0.10 --db-name fireflo --db-user fireflo --db-password-file /root/fireflo-db.pw
```

`--node-id` is required for a new install here: a default would give two hosts
the same id. Further nodes join instead of bootstrapping — after the `--`,
`--join --config-source db --secrets-key-file <file>` and the database flags,
as in [Multi-host and clustering](#multi-host-and-clustering). Without
`setup.sh`, the same is `fireflo-install install --from ./gateway --role
gateway --kafka-bootstrap 10.0.0.20:9092 --node-id gw-1 …`, or `fireflo-install
update --kafka-bootstrap 10.0.0.20:9092 --migrate` on a gateway that already
runs (drained, as above). If the broker does not answer within two minutes
(`--broker-wait` to change it), the gateway is not touched.

### Checking it worked

```
sudo /opt/fireflo/bin/fireflo health
sudo /opt/fireflo/bin/fireflo broker test --bootstrap 127.0.0.1:9092    # or 10.0.0.20:9092
```

In `health`, `backbone` is there with `"connected": true` and the bootstrap you
gave; `router_lag` is the router's backlog on the topic and should sit near 0.
No `backbone` at all means the gateway is still on the in-memory queue. `broker
test` dials the broker the way the gateway does and prints the cluster id, the
brokers and the controller.

### Redpanda or Kafka

- **Redpanda** (the default): one binary from Redpanda's package repository; sizes itself to the machine, so wants 4 GB and more, and is the one to choose for a three-node broker cluster (`--ips`).
- **Apache Kafka** (`--broker kafka`): one KRaft node from the apache.org tarball, a JVM with a fixed heap (`--kafka-heap`, 1g), so the better fit for a small VM; a Kafka cluster you build yourself (`--kafka-kraft-notes`).

## Preparing a host

`setup.sh` installs the services FireFlo talks to. It exists because the
gateway's own installer does not: `fireflo-install` adds the PostgreSQL
**client** and no server, and never installs a broker — so between unpacking the
tarball and running the installer there is a step that was only ever written
down in prose.

```
sudo ./setup.sh --dry-run     # read what it would do first
sudo ./setup.sh
sudo ./setup.sh --help        # every flag, and why each default is what it is
```

**Hosts.** Ubuntu focal, jammy, noble and plucky, and Debian bookworm and
trixie, through `apt`; RHEL 9, CentOS Stream 9, Rocky Linux 9 and AlmaLinux 9
(and newer), through `dnf`, from BaseOS and AppStream only — no EPEL. Debian
bullseye is recognised but refused, because its PostgreSQL is 13 (see
[Before you begin](#before-you-begin)). Anything else is refused by name.

**Roles.** `--role` says which machine this is:

| Role | Installs |
|---|---|
| `all` (default) | Everything on one box: PostgreSQL, a single broker node on 127.0.0.1, Node 22 for the control panel, the gateway's client tools. `--no-postgres` and `--no-node` leave either out |
| `gateway` | Client tools only — no database, no broker, no Node. Nothing on a gateway node holds state |
| `db` | The PostgreSQL server the gateway nodes share. `--allow-from CIDR` (repeatable) edits `listen_addresses` and `pg_hba.conf` for that subnet, backing each file up first; without it the lines are printed for you to apply |
| `broker` | One broker node, advertising `--advertise-ip` (default: the first non-loopback address, printed so you can check it). For a three-node Redpanda cluster, run it on each with `--ips A,B,C` |
| `panel` | Node 22 and a PostgreSQL client |

**The broker.** `--broker redpanda`, the default, is one binary from
Redpanda's own apt or rpm repository (`REDPANDA_VERSION` pins it).
`--broker kafka` is Apache Kafka in KRaft mode, one node, from the
downloads.apache.org tarball with its SHA-512 checked (4.4.0 unless
`KAFKA_VERSION` says otherwise), run by a systemd unit it writes — a JVM with a
fixed heap (`--kafka-heap`, 1g), which suits a small VM better, and needs
Java 17 or newer (`--with-java` if the host has none). Either is optional: a
gateway without `--kafka-bootstrap` uses its in-memory queue and never talks to
the broker. `--configure-gateway` points the gateway at it in the same run — see
[Install and configure Kafka](#install-and-configure-kafka).

Java is **not** installed unless you pass `--with-java`: the gateway is a native
binary and opens no JDK, so a JDK is only wanted for building from source, for
the Java build on ARM, or for `--broker kafka`.

**It creates no database, no role and no password**, and no broker user, ACL or
SASL. Installing a package is impersonal and reversible; minting a credential
and writing it to disk is neither, and it is not a decision a setup script
should take for you. It prints the commands to run instead.

**It writes no firewall rules and never changes SELinux.** Which hosts may
reach which port is a fact about your network, and a firewall on a host you are
ssh'd into is not something to change from a script. It prints the lines per
role — `ufw` on Ubuntu and Debian, `firewall-cmd` on RHEL-family hosts or
wherever firewalld runs — and, on an Enforcing host where a data directory has
moved, the `semanage` and `restorecon` lines.

**`setup.sh` is not signed**, unlike the release tarball — it is a plain script
in this repository rather than a build artefact. It is one readable file whose
only network fetches are the repositories it names (NodeSource, Adoptium,
Redpanda) and the Apache Kafka tarball, so read it before you run it as root.

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
the broker and Node alone, because `setup.sh` installs those host-wide and a
second tenant is probably still using them.

**SMPPSim is not removed by it yet.** An install made with `--with-smppsim` has
its own unit and directory; remove them by hand:

```
sudo systemctl disable --now fireflo-acme-smppsim
sudo rm /etc/systemd/system/fireflo-acme-smppsim.service && sudo systemctl daemon-reload
sudo rm -rf /home/acme/smppsim        # or /srv/fireflo/acme/smppsim, /opt/fireflo-smppsim
```

**Release the licence in your account before running it, not after.** A licence
still bound to a host that no longer exists has to wait out the tolerance window
before another machine can take it.

## Earlier builds

**Only the current release is published here.** Builds before 0.12.10 have been
withdrawn and their tarballs removed from this tree. 0.13.5's last tarballs (with
control panel 0.13.5.0) are in this repository's history at commit `e110799`. 0.13.4's last tarballs (with
control panel 0.13.4.4) are in this repository's history at commit `30ee812`. 0.13.0's last tarballs (with
control panel 0.13.0.2) are in this repository's history at commit `9102ba0`. 0.12.36's tarballs (with
control panel 0.12.36.0) are in this repository's history at commit `0821a8b`. 0.12.35's tarballs (with
control panel 0.12.35.0) are in this repository's history at commit `88159a1`. 0.12.34's last tarballs (with
control panel 0.12.34.6) are in this repository's history at commit `c95aa37`. 0.12.33's tarballs (with
control panel 0.12.33.0) are in this repository's history at commit `b35bfe6`. 0.12.32's tarballs (with
control panel 0.12.32.0) are in this repository's history at commit `ec03260`. 0.12.31's last tarballs (with
control panel 0.12.31.1) are in this repository's history at commit `d7b0f65`; its first (with
control panel 0.12.31.0) are in this repository's history at commit `4c0443a`. 0.12.30's tarballs (with
control panel 0.12.30.0) are in this repository's history at commit `edd265d`. 0.12.9's tarballs (with
control panel 0.12.9.0) are in this repository's history at commit `d39e2df`. 0.12.8's last tarballs (with
control panel 0.12.8.2) are in this repository's history at commit `0463a83`; its first
(with control panel 0.12.8.1) at commit `d1e0f81`. 0.12.7's tarballs (x86-64, and
the Java build for ARM) are in this repository's history at commit `3d945dc`. 0.12.6's tarball (with
control panel 0.12.6.1) is in this repository's history at commit `4f8cea3`. 0.12.5's last tarball (with
control panel 0.12.5.1) is in this repository's history at commit `23ca28b`; its first (with
control panel 0.12.5.0) at commit `1a8f540`. 0.12.4's tarball is in this
repository's history at commit `9d0ef1f`. 0.12.3's last tarball (with
control panel 0.12.3.1) is in this repository's history at commit `4bc5ec8`; its first (with
control panel 0.12.3.0) at commit `43d3446`. 0.12.2's tarball is in this
repository's history at commit `dc1022b`. 0.12.1's last tarball (with
control panel 0.12.1.1) is in this repository's history at commit `357f19b`. 0.12.0's tarball is in this
repository's history at commit `25983af`. 0.11.5's last tarball (with
control panel 0.11.5.3) is in this repository's history at commit `e33fd0e`.
0.11.4's last tarball is in
this repository's history at commit `adf5cca`. 0.11.3's last tarball is in
this repository's history at commit `2af1923`. 0.11.0's is still in this
repository's history, at commit `42d506e`, and is where the REST panel lives
for now.

### 0.14.0 with control panel 0.14.0.0

**RabbitMQ is removed** (breaking). `smsg.queue.provider` is `memory` -- the default, one gateway,
behaviour unchanged -- or `kafka`. A stored `rabbitmq` refuses to start; `fireflo-install update`
finds it before stopping anything and prints the drain procedure (stop customer intake, wait until
the broker queue and the router queue are empty, then `update --no-broker` or `--kafka-bootstrap
host:9092`). `--broker-uri` and `--broker-queue` are refused. See
[Upgrading from 0.13.x](#upgrading-from-013x). Gateway `036a71f`, schema 1.109.0, control panel
0.14.0.0 (`8d83df4`).

- **Kafka backbone, optional.** With `--kafka-bootstrap`, every hand-off inside the gateway goes
  through Kafka (Apache Kafka 4.x in KRaft mode, or Redpanda). A message is acknowledged to the
  customer only after the broker has it; routing rules from the control panel are applied by the
  gateway's router reading the router topic; one topic per vendor; retries through delay topics; a
  dead-letter topic; webhooks that survive a restart. There is no fallback to memory: with the
  broker down the gateway answers SMPP `ESME_RMSGQFUL` and HTTP `503`. The gateway creates its
  topics at start, or ahead of time with `fireflo broker init`.
- **Kafka mode is cluster mode.** Several gateway nodes on one PostgreSQL and one Kafka, each with
  its own `FIREFLO_INSTANCE_ID` (`--node-id`). Each vendor is leased to one node at a time and moves
  automatically when that node dies; receipts are delivered to the node holding the customer's
  bind; credit is held per node; rate limits are split by where each customer is bound; dead nodes
  are cleaned up. See [Multi-host and clustering](#multi-host-and-clustering).
- **A message no rule routes is refused at the door.** It used to be accepted, retried and
  refunded; now SMPP answers `0x0000000B` by default (`conf.status.noRoute`, settable per listener)
  and HTTP `403`. `smsg.routing.ingress.check=false` restores the old behaviour.
- **Copy routes:** the first target owns the charge and the receipts; the copies are unbilled and
  send no receipts.
- **Upgrading from 0.13.x is a maintenance window.** Migration V1.105.0 (credit held per node)
  needs every gateway stopped. `fireflo-install update` handles one node; with several, stop each
  (`fireflo-install service stop`), then `--migrate` on the first and `--no-migrate` on the rest.
  Credit held under the old host-name owner carries over.
- **Installer flags.** `fireflo-install` gains `--kafka-bootstrap`, `--kafka-security`,
  `--kafka-sasl-mechanism`, `--kafka-sasl-user`, `--kafka-sasl-password-file`,
  `--kafka-truststore`, `--kafka-truststore-password-file`, `--kafka-topic-prefix`,
  `--kafka-partitions`, `--node-id`, `--role gateway`, `--join` (node 2 onwards, with
  `--secrets-key-file`), `--migrate`/`--no-migrate` and `service stop`. `fireflo-panel-install`
  gains `--gateway-ops-url`, `--gateway-base-url`, the `--db-*` flags with `--db-password-file`, the
  token and secret files, and `--gateway-ops-urls id=url,...`, for a panel on a host of its own.
- **`setup.sh` is new:** host roles (`--role all|gateway|db|broker|panel`), the broker choice
  (`--broker redpanda`, the default, or `--broker kafka` for Apache Kafka 4.4.0 in KRaft mode,
  SHA-512 checked), RHEL-family 9+ hosts through `dnf` beside Ubuntu and Debian through `apt`,
  `--allow-from` for the database host, and firewall and SELinux steps printed rather than applied.
  See [Preparing a host](#preparing-a-host).

### 0.13.5

**Billing and receipt fixes from a routing/billing/DLR audit.** No schema change (still 1.102.0);
update as for 0.13.4. Gateway `7f73b38`, control panel 0.13.5.0.

- **A long message is refunded once.** When the gateway split a message into parts and the vendor
  refused some of them, each refused part refunded the whole message price -- so a customer could
  be credited two or three times for one message. Now one refund per message, and none once the
  vendor has accepted any part of it (it carried that part and charged for it); the customer's
  receipt still says FAILED.
- **Late receipts reach the customers the deadline did not answer.** The 24-hour UNKNOWN job marked
  every overdue message, including those it then sent nothing to (excluded accounts, customers who
  asked for no such receipt, no listener or webhook). Their real receipt, arriving later, was then
  suppressed. Only messages actually told UNKNOWN are marked now.
- **Every part's receipt is counted.** Receipts for the parts of one message arriving together
  could lose a count, so a delivered message ended UNKNOWN and then EXPIRED. A message closed by a
  refused part can no longer be re-opened by a later part, which gave a second receipt and a second
  final record.
- **Billing zone:** a gateway that takes its zone from `FIREFLO_BILLING_ZONE` writes it to
  `smsg.billing.zone` in `app_config` at start-up when that row is missing, so the control panel
  cuts billing days in the same zone. A row that is already set is never changed; a mismatch is
  logged as `billing.zone.mismatch`.
- **Control panel 0.13.5.0:** Revenue, Usage and Accounts at 7 and 30 days no longer count the
  hours before the hourly summary began as empty.

### 0.13.4 with control panel 0.13.4.4

Same gateway (`b611256`, schema 1.102.0); the tarballs carry the newer control panel. Install or
update as for any 0.13.4 build -- `fireflo-panel-install update` brings an existing panel to it.

- **Heavy stats no longer time out.** Usage and Revenue read the gateway's hourly summary while it
  is current (a 24-hour window used to read every message of the day); Receipts finds its sample's
  receipts by index instead of scanning the window (30 days on a few million messages went from a
  timeout to about a second). Their answers are kept and shared for a while (5 min for a week or a
  month), at most three heavy reads run at once, and a read that takes long shows a "taking a
  breath" card and finishes in the background instead of "canceling statement due to statement
  timeout".
- **Charts:** Receipts (how each vendor's attempts ended; time to receipt) and Revenue (revenue by
  period as cost plus margin; top accounts).
- **The last hour first:** every traffic page opens on 1 hour, remembers the period its user last
  chose, and a listener page shows its traffic by account. Messages has a one-row filter bar, with
  a right-hand drawer on phones and its filters kept between visits.
- **Smaller things:** pin pages to the top bar; one stats API for the panel and the portal
  (`/api/stats/<metric>`, old routes kept); loading shown on the control that asked; copy buttons
  that work over plain HTTP; Space Grotesk / DM Sans on Tailwind's type steps.

### 0.13.4

**Native builds: the Security, Slow queries and whitelist tester pages work again.** On 0.13.0 to
0.13.3 a native gateway answered "The field at path '/refusalSummary[0]/byReason[0]/reason' was
declared as a non null type, but … returned a null value": the records behind `refusals`,
`refusalSummary`, `slowQueries`, `slowQuerySummary` and `whitelistTest` were never registered for
reflection, so the native image read every field as null. The Java build was unaffected.
**Security:** a customer's SMPP bind password no longer reaches `smsg.log` -- the SMPP library
(the EdgeServers fork, now 7.2.4) logged every bind PDU, password included, before any per-account
logging applied. Existing logs keep what was written: rotate or scrub `smsg.log` on gateways that
carried SMPP customers on 0.13.3 or earlier. No schema change (still 1.102.0). Control panel
0.13.4.0 is 0.13.3.3 renumbered to pair with it. Gateway `b611256`.

### 0.13.3

**The native build's management port works again.** On 0.13.0 to 0.13.2 the native gateway answered
500 to every GraphQL request on port 9000 -- graphql-java's message bundles were in the image but
not registered as bundles, so a document could not even be parsed. The Java build (the ARM tarball,
and the staging gateway) was never affected, which is how it went unnoticed. Nothing else changes;
control panel 0.13.3.0 is 0.13.2.0 renumbered to pair with it. Every native install on 0.13.x
should take this release. **Control panel 0.13.3.1** sets the panel in Noto Sans with a type scale built
for it -- page titles 28px, entity names 22px, card titles 17px, section titles 15px, body 14/22,
help text 13/20, figures 30px -- and retunes card, table, sidebar and dialog spacing to match; the
gateway is unchanged. **Control panel 0.13.3.2** darkens body text to near-black and
secondary text to slate-600, draws a listener's Disable as a danger button with Force disconnect
in the card footer and a session's Disconnect as an icon, and puts "Page generated in N s" in
every operator page's footer in place of the version. **Control panel 0.13.3.3** makes the Receipts page answer
within seconds on a busy gateway (counts from the hourly summary, timings from a fixed sample;
it used to hit the 10 s statement timeout past a day of traffic), and fixes "GATEWAY_BASE_URL and
GATEWAY_OPS_TOKEN must both be set" on panels upgraded to 0.13: `fireflo-panel-install update`
now writes `GATEWAY_BASE_URL` (the gateway's main port, where 0.13 serves its metrics) when it is
missing. Gateway `623e915`.

### 0.13.2

**`Session.receipts`.** Session rows on the management port (the `sessions` query and the health
snapshot) carry the deliver_sm the gateway sent down a bound customer's session since the bind --
delivery receipts and inbound messages -- beside what the customer submitted; declared as the
capability `session_receipts`. No schema change (still 1.102.0). **Control panel 0.13.2.0** uses it
on a listener's page: the Status tab gains *Traffic by account* (MT received and DLR delivered per
connected account and overall, live), and the Connections tab folds binds under their account --
one row per account with the binds counted by kind (2 TX · 2 RX), each bind under it identified by
address and source port with Capture and Disconnect on that row, and Expand all beside Refresh.
Gateway `575f623`.

### 0.13.1

**`health.currency`.** The management port's `health` now carries `smsg.rates.currency` as the
gateway reads it, file or database. The control panel (0.13.1.0) reads it when the key is not in
`app_config`, which is every file-mode gateway, so opening a balance never asks for a currency the
platform already has and statements and reconciliations name it. No schema change (still
1.102.0). Control panel 0.13.1.0 also lets an account's notes run across the whole settings row. **0.13.1.1 redesigns the Security page**: one time range for the whole page, one Refused logins card with By address, By server port and Every attempt tabs sharing a filter row, per-port and per-reason columns from the gateway's ledger merged into the address rows, Ban/Unban/Hold/Lift on the row with the fail2ban jail and duration chosen inline, automatic-ban rules as settings rows, and a uniform tools rail.
Gateway `cb84f11`.

### 0.13.0

**The management port is GraphQL-only** (breaking). Everything that was `GET`/`POST /ops/...` on
port 9000 is now a query or mutation at `POST /graphql` on the same port, with the same two bearer
tokens (the admin token now also answers reads); `/ops/*` answers 404. A new allow-list,
`FIREFLO_OPS_ALLOWED_IPS` (addresses or CIDR blocks; empty means loopback only), is checked before any
token, so `FIREFLO_OPS_HOST=0.0.0.0` on its own exposes nothing. `/q/metrics` moves to the main
port, behind the ops read token (`bearer_token` in your Prometheus scrape); it is gone from 9000.
**Update together:** the control panel (0.13.0.0, which needs schema 1.102.0), `scripts/fireflo`
(shipped here; `fireflo verify` now prints a licence line), and anything of yours that scraped
`/ops/health` or `/q/metrics` on 9000. The customer API (`/secure/*`) and `/manage/*` are unchanged.

**The platform API on the same port.** A platform such as FireFlo OMNI 1.1 manages its accounts
through `/graphql` only, signed with the management token: accounts, balances, ledger, usage,
messages and outcomes as paged feeds, sends under an account, provisioning, tariffs, logins and
registrations. OMNI 1.1 needs this release: upgrade gateways first, then OMNI, and allow-list OMNI's
address. One additive migration, **V1.102.0**: sync indexes on the call records (minutes per large
month partition -- run `update` in a quiet window), `cdr_final.account_id` (filled for old rows by the
`backfillOutcomeAccounts` mutation, otherwise found through a join), a `fireflo_sync` read-only role
when the migrating role may create one (else `conf.example/sql/fireflo_sync.sql`), and a new
`FIREFLO_SYNC_DB_*` datasource (pool 4, 5 s statement timeout) so sync traffic never starves sending.

**Slow query log.** Every statement the gateway runs is timed; those over `FIREFLO_DB_SLOW_MS`
(500) are kept in memory with their SQL shape (never a value) and shown on the control panel's new
Database → Slow queries page, with `fireflo_db_query` and `fireflo_db_slow` meters.

**Refused logins by server port.** Each refused bind now records its listener and port
(`auth-failed.log` gains `listener=... port=...` before `ip=`; the shipped fail2ban filter matches
both the old and the new line), the connection-limit and back-off refusals that were only counters
are recorded too, and the Security page gets a *By server port* view: per listener, by reason and
address, with **Ban in fail2ban** (the sudo wrapper gains a `ban` verb -- re-run
`fireflo-install fail2ban`) and rules that ban automatically after a dry run.

Control panel 0.13.0.2 (0.13.0.1 moved its Security and Slow queries pages under Reports; 0.13.0.2 stops asking for a currency when opening a balance wherever the gateway already holds one -- on a file-mode gateway the panel now reads the gateway's own `explicit_currencies` view, and asks only on a platform with nothing priced or funded yet; 0.13.0.0 was the first cut, all with the same gateway); gateway `272b619` (0.13.0 plus the native-image fix that follows it).

### 0.12.36

**The management API a platform needs** (V1.101.0, one additive migration: `app_account.external_ref`
and `app_rate_rule.managed_by`, both empty on existing rows -- `update` applies it in seconds). A
platform such as FireFlo OMNI now marks the accounts it created (`ref` on `POST /manage/accounts`;
an id another platform owns, or nobody does, is refused with `OWNED` / `UNOWNED`), lists the gateway's
products (`GET /manage/products`), asks what a destination costs (`POST /manage/quote`), writes a
**custom tariff** for one account (`PUT /manage/accounts/{id}/tariff`: only the rules it owns are
replaced, they sit ahead of yours, another currency is refused), sets which products an account's
login may send (`PUT …/products`) and creates **SMPP logins on request** (`POST …/logins`: an
8-character system id and password, shown once). Every accepted HTTP send and batch callback now says
what it cost (`price`, `currency`, `segments`, or `unrated`).

**Control panel 0.12.36.0.** An account a platform manages shows "Managed by" with its marker, and the
tariff rules the platform wrote are read-only ("Set in OMNI"). SMPP logins get an 8-character
generated system id (a typed one is capped at 15) and 8-character passwords, so they fit the
protocol. The panel needs schema 1.101.0. Gateway `d8ed07b`.

### 0.12.35

**Headers and Templates show each registration in full** (Assets). Over each list, how many there
are, how many wait for approval, are refused or withdrawn, and how many of the listed accounts
enforce it. Chips filter by status (all, waiting, refused, approved, withdrawn) with their counts,
beside an account picker and 25, 50 or 100 rows a page -- all done by the database. A sender ID
shows its account's name and whether it enforces, its product and login, its stamps and any change
the customer proposed, who asked for it, who reviewed it and why it was refused. A template shows
its text on its own line with the variables marked, how many variables and of what kind, and its
length as GSM-7 or Unicode with the number of SMS parts. Open a row for the request note, every
stamp on the wire (accept or dismiss proposed stamps there), missing stamps with their fixes, and
the history.

The gateway is unchanged apart from its version: no schema change (still 1.100.0), so `update` has
nothing to migrate. Everything else listed under 0.12.34 below -- archived accounts, moves, the
dashboard sunbursts, the account Overview fix -- is in this release too. Control panel 0.12.35.0;
gateway `c0581ec`.

### 0.12.34

**Archive an account** (Accounts → an account → Settings, admins). Archiving retires an account
without deleting it: its logins are switched off and any live SMPP binds dropped, nobody can sign in
to the portal for it (a sign-in link sent earlier stops working too), it leaves the account list for
an "Archived" view, and it becomes read-only. The credit the gateway holds for it goes back to its
balance; the balance, statement and call records stay. Unarchive switches back on exactly the logins
the archive switched off. A reseller with active customers cannot be archived. The gateway withholds
an archived account's logins, and its management API refuses to top up or re-provision one (409).

**Move a login, sender ID or template to another account** ("Move…" on the Logins tab, the move icon
on Approvals). A login moves alone: it is refused while sender IDs or templates are scoped to it,
and its live binds are dropped so it re-binds billing the new account. A sender ID or template keeps
its approval. What was already sent stays on the old account.

**Dashboard.** Two sunburst charts side by side: why messages failed (accounts inside, each split by
reason) and sent by vendor (vendors inside, each split into delivered, failed and pending), with
their tables on demand. Click a slice to zoom into it; the centre or the breadcrumb zooms back out. Both follow the 24 hours / 7 days / 30 days toggle with the tiles and the
traffic chart, and come from the same background snapshot: the hourly summary for whole hours,
the call records only past its watermark; each says which it read. The vendor figures (dashboard
and Vendors page) now read the call records by index -- 1.3 s became a few milliseconds on a
3.7-million-row test database. Measured TPS shows at most two decimal places. The routing and pricing rule
dialogs no longer stretch the When switch beside a squeezed condition editor.

**Accounts and assets.** An account's Overview tab reads only that account, and its 7 and 30 days
from the hourly summary: it no longer hits the statement timeout. The Headers and Templates pages
are paged, searched and filtered in the database, 25 rows at a time.

**Schema V1.100.0** adds three empty columns to `app_account` (`archived_at`, `archived_by`,
`archived_logins`); nothing existing changes. Update the control panel with the gateway: a panel
older than 0.12.34 warns that the schema is newer than it expects. Control panel 0.12.34.6; gateway
`11527cc`.

### 0.12.33

**Template variables written together are one variable.** Assets → Templates now accepts DLT-style
templates such as `Your OTP is {#var#}{#var#}{#var#}`. Placeholders of one type that touch, or are
separated only by spaces, act as one variable of their combined length: three `{#var#}` stand for 1
to 90 characters at the default limit of 30. A space between them is optional, so `{#num#} {#num#}`
accepts `1234 5678` and `12345678`. Digits next to letters (`{#num#}{#alp#}`) split where the type
changes. `{#var#}` touching `{#num#}` or `{#alp#}` is refused when the template is saved, because the
split point could not be known. The template form shows each group and its length under the preview.
An approved template like `Code {#var#} {#var#} end` now also accepts the two values written without
the space.

**Behaviour change: SMPP delivery receipts come from the handset.** Every receipt went out from the
customer's own sender ID to the handset -- the opposite of SMPP practice and of Kannel. It now goes
from the handset (the number the message was sent to) to the customer's sender ID. A customer whose
receipt parser was written against the old order can keep it: set `flag.reverseDlrSrcDst=true` on
that customer's listener. Routing rules are unaffected.

No database migration (the schema stays at V1.99.0).

### 0.12.32

**A funded account is no longer refused for credit.** An SMPP client sending back to back on a
prepaid account was told `0x402` "insufficient credit" on its last twenty messages' worth of balance
-- an account funded for thirty messages got twenty through and ten refused. The gateway reserves
credit in blocks; when what was left could not fill a block, it treated the account as empty for a
second, and the messages in that second were refused although the balance covered them. Now an
account is only treated as empty when it cannot pay for the message in hand. Small accounts, which
always held less than a block, were the most affected.

**A throttled client is named in the log.** A client over its rate used to put one line per refused
message in `smsg.log`, naming only a session number. Now one line per session, at most every ten
seconds, names the account, the login, the address, which limit tripped and how many were refused:
`smpp.throttled account=… systemId=… ip=… limiter=account rate=5/s throttled=54 …`. The new metric
`fireflo_smpp_throttled_total{limiter="account"|"login"}` counts every `0x58`.

**The insufficient-credit status, per listener.** `0x402` -- what the gateway has always answered --
is also the vendor code for "number unroutable, do not retry", so a client reading the usual tables
drops the message instead of retrying after a top-up. A listener can now answer `0x401`
("insufficient credits") with `conf.status.insufficientCredit=0x401`. The default stays `0x402` so no
client sees a different code on upgrade; we recommend moving each customer port to `0x401` once its
clients are ready, and the default will change in a later release, announced first. Refusals are
recorded as `insufficientCredit` either way.

No database migration (the schema stays at V1.99.0). Control panel 0.12.32.0 changes only its
version, to pair with this gateway.

### 0.12.31

**Control panel 0.12.31.1** (the gateway is unchanged; the tarballs were re-cut with the new panel).
An account's Settings tab showed *Name this account* for a moment on every account while the
catalogue loaded, and saving it sent a name alone -- which blanked the account's email and
description and, for an operator, reset reselling and the reseller it belongs to. A save now keeps
every field it does not carry, on the operator panel and the portal alike, and the tab waits for the
catalogue before offering either form. On the Gateway page switches, number boxes and lists keep
their own width instead of stretching across the column; the top bar's health, theme and account
menu sit at the right edge on a wide screen; and the TLVs a header, template or login stamps show as
an *N stamps* chip that opens the list, instead of widening the table.

**The control panel, redesigned.** A neutral palette (green is the mark and the success state, nothing
else); a top bar on every page with Messages, Vendors, Servers and Accounts as tabs, a jump box
(⌘K / Ctrl+K) that opens an account, a vendor, a server or a message by id, the gateway's health as
one word with its outbound rate, and an account menu holding Change password and Sign out; forms laid
out as settings rows -- the setting and its help on the left, the control on the right -- on the
Gateway, vendor, server, login, account, pricing, routing and TLV screens; stat tiles without icons;
cards without shadows. The customer portal runs on the same frame with its own map, its balance in
the sidebar and the top bar, and Accounts shown only to a reseller.

**Fixed with it.** A reseller's child-statement CSV was the reseller's whole book; it is the child's.
*Close this period* asked nothing; it confirms, naming the period and the amount. A white-labelled
portal showed FireFlo's mark; it shows the operator's logo (new optional `MIS_PANEL_LOGO_URL` beside
`MIS_PANEL_BRAND`) or the brand's initial. An operator could name a brand-new account with a vendor's
name or a malformed id; both are refused, and the Settings tab now shows a refusal instead of
swallowing it. A gateway setting the host supplies (an env var, or the shipped `application.properties`
line for keys such as `smsg.cdr.body`) was shown as *Set on the host* and locked, so message-text
retention could not be switched on from the panel; the gateway reads a saved value before the host's,
and the row is editable again.

**Gateway:** no functional change since 0.12.30 (one test). **No migration** -- the schema stays
1.99.0. Upgrading from 0.12.30 is the gateway binary, the panel source and `npm ci && npm run build`;
from 0.12.29 or earlier, apply the 0.12.30 notes below first.

### 0.12.30

**A message whose receipt never comes gets a final UNKNOWN receipt.** At the receipt deadline
(`smsg.cdr.deadline.hours`, 24 hours) a message still waiting for its outcome was closed as EXPIRED in
the call records and the customer was never told. It is now sent one final receipt, `stat:UNKNOWN` with
`err:000` by default: over SMPP through the listener it arrived on (held and replayed at the next bind
when the login is not bound), or to its webhook. `registered_delivery` decides whether it is owed. A
vendor receipt arriving later is recorded and shown in the panel, and not sent: the customer is never
told two outcomes for one message. Each node tells the messages it took. Settings, under Settings →
Receipts: `smsg.dlr.deadline.receipt.enabled` (true), `smsg.dlr.deadline.receipt.err` (`000`) and
`smsg.dlr.deadline.receipt.exclude.accounts`.

**Before upgrading:** within ten minutes of the first start, customers are sent UNKNOWN for every
message already past the deadline with no outcome and still in the receipt store (up to
`smsg.dlr.retention.days`, 7). List the accounts that must not get them, or switch the feature off,
beforehand. Messages taken before 0.12.25 are not reached.

**One migration, V1.99.0:** the three settings registered, and the registered default of
`smsg.cdr.deadline.hours` corrected from 48 to 24 -- what the gateway has always used. Carries 0.12.29
and 0.12.28, which were not published here; their notes follow.

### 0.12.29

**The home page's failures tile loads again on a busy gateway.** It grouped the last day's failed
messages from every call record in the window; at about a million records a day that ran past the
control panel's 10-second limit every minute and the tile showed "stale: failures". The gateway now
keeps failures per hour by state, receipt status and error code beside its hourly usage summary, and
the panel reads whole hours from it and only the last minutes from the records. The tile's counts move
when an hour is recomputed (every 15 minutes by default) and its window starts at the top of the hour.

**One migration, V1.98.0:** table `usage_failure_hourly`, backfilled during the upgrade from the call
records already there (about 40 seconds for ten days at a million a day). Run it with the gateway
stopped, as the installer does.

### 0.12.28

**Each vendor connection stays on its own link.** With two or more vendors, connections opened at the
same moment -- at start-up, or a reconnect overlapping another vendor's -- could be built on each
other's socket: messages routed to one vendor went out through another and were recorded under the
first ("Duplicate handler name: smppSessionThreadRenamer" in the log). A single-vendor install was
never affected. **A group re-route tries another member:** a message a vendor hands back for
re-routing (`status.retry.router`) no longer goes straight back to it while another member is up.
**The control panel confirms changes** on the vendor, server, account, pricing and routing screens, and
asks for DELETE before deleting. No migration.

The licence key in the binary is unchanged. 0.12.27's tarballs are in this repository's history at
commit `61e59b3`.

### 0.12.27

**Vendor attempts survive an hour's last summary pass.** 0.12.26 added per-vendor attempts to the
hourly usage summary and recounted them under the rule that stops a settled hour from changing --
right after the same pass had marked the hour as just recomputed. An hour past the receipt deadline
therefore read as settled and kept the zero the pass had cleared it to: every hour lost its attempts
at its last recount, and so did every hour `fireflo usage hourly --backfill` computed. Attempts are
call record rows that never change, so they are now recounted at any age. If you ran 0.12.26, run
`fireflo usage hourly --backfill 35` once after upgrading to repair the hours already affected.

**Hours before the summary began are no longer counted as empty.** On an install that enabled the
hourly summary late, the control panel's vendor figures read those hours from the call records (slower,
but right) until the backfill summarises them. On a staging gateway the 7- and 30-day figures had come
out equal, a week of records short.

**No migration** from 0.12.26; coming from 0.12.25 or earlier the 0.12.26 notes apply first (V1.97.0).
The licence key in the binary is unchanged. 0.12.26's tarballs are in this repository's history at
commit `46975b3`.

### 0.12.26

**Vendor traffic loads at once instead of timing out.** The vendor page and the Vendors list
computed their figures from every call record in the range on each load: a distinct count of message
ids, the representative attempt of every message, and a receipt lookup per message. On a few million
records that ran past the control panel's 10-second statement timeout ("canceling statement due to
statement timeout"). The gateway's hourly usage summary already held each message's count, outcome
and cost under the vendor that carried it; it now also counts **attempts by the vendor each attempt
went to** (a failover refusal is real load on the first vendor). The panel reads whole hours from the
summary and only the opening part-hour and the last minute or two from the records. Measured on 2.3
million records over two and a half days: the same figures for every vendor, in 0.1 s instead of
8.7 s. A gateway before 0.12.26, or a stalled rollup, keeps the old query.

The control panel also expects the right schema again: 0.12.25.0 still expected 1.95.0 and showed
"Database schema 1.96.0 is newer than this panel expects".

**One migration, V1.97.0:** adds `usage_hourly.attempts` and backfills it for the hours the summary
already covers (35 days by default), reading that range of call records once. Run it with the gateway
stopped, as the installer and `fireflo-install update` do. The licence key in the binary is unchanged.
0.12.25's tarballs are in this repository's history at commit `953cc3c`.

### 0.12.25

**Call record inserts stay flat as the tables grow.** Every call record table is indexed on the
message id, and the id was a random UUID, so each insert landed on a random page of each of those
indexes. While they fit in memory that is cheap; once they do not, every message costs random disk
reads and writes, and more of them as the table grows -- the limit at ten million records a day.
Message ids are now **UUID version 7**: the same 36-character form, ordered by time, so new ids land at
the end of every index keyed on them. Measured, 200,000 inserts into a 5-million-row id index: 3 pages
read from disk instead of 128,082, 4,267 dirtied instead of 129,779. Existing ids are untouched; a new
id reveals when it was made, to the millisecond.

The message body search and multipart lookup indexes now cover only the rows that have something to
index (almost every row has neither), and searches still use them. Three indexes left by the 0.12.10
partitioning that duplicated others on the current partition are dropped.

**One migration, V1.96.0:** rebuilds the two indexes, reading `cdr_submit` once while call record
inserts wait -- seconds on a few million rows, longer on hundreds of millions. Run it with the gateway
stopped, as the installer and `fireflo-install update` do. The licence key in the binary is unchanged.
0.12.24's tarballs are in this repository's history at commit `5b58e2a`.

### 0.12.24

**The ~500 messages a second ceiling, removed.** A vendor's delivery receipt was handed to the router
with a blocking put into the bounded router queue -- the queue new submits fill -- on the same
connection thread that reads the vendor's `submit_sm_resp`s. Under load the receipt waited for room,
the responses went unread and expired, the vendor's window stayed full, and the router could not hand
it anything. Throughput settled near 500/s whatever the hardware, and the listener refused the rest
as queue full (`ESME_RMSGQFUL`). Receipts and inbound messages from a vendor now never make that
thread wait: when the router queue is full they wait in an ordered overflow drained by its own thread.

Measured with a test vendor returning a receipt for every message, 3,000/s offered for 60 s: about
520/s accepted before; 3,000/s sustained after, every receipt delivered, the gateway using about one
core. The first seconds after a start still refuse some traffic while the JVM warms up.

**No migration** from 0.12.23; coming from 0.12.22 or earlier the 0.12.23 notes apply first (V1.95.0).
The licence key in the binary is unchanged. 0.12.23's tarballs are in this repository's history at
commit `bcb0625`.

### 0.12.23

**Prepaid spending is no longer refunded by a restart.** A gateway moves credit from `balance` into
`reserved` in blocks and spends it in memory, and nothing ever took the spending out of the database:
`reserved` held spent and unspent credit alike. The reclaim on start added in 0.12.10 (V1.79.0)
returned everything an instance held to `balance`, so **every restart from 0.12.10 to 0.12.22 refunded
the prepaid spending since the one before.** On a staging gateway an account was back at its starting
balance after about 120,000 charged messages and four restarts.

The gateway now settles its spending every `smsg.balance.settle.seconds` (default 5) and on release or
shutdown: `reserved` goes down by what was spent and the new `account_balance.spent` goes up, with a
`SPEND` row in `balance_reservation` each time. A restart returns only credit that was held and not
spent; a crash returns at most the last settlement interval's spending. The money identity is now
`credited = balance + reserved + spent`, and the control panel's reconciliation reads it that way.

**If you ran 0.12.10 to 0.12.22 with prepaid credit on,** account balances may be higher than what was
paid for, by the prepaid spending between restarts. Nothing in the database tells the refunded spending
apart from real top-ups; the call records (`cdr_submit.price`) are what was actually sent.

**One migration, V1.95.0:** adds `account_balance.spent`, lets `balance_reservation` hold `SPEND`, and
moves whatever is in `reserved` to `spent` -- under the old bookkeeping that amount is spending, since a
stopped gateway has already handed back what it had not spent. **Run it with every gateway stopped**
(the installer and `fireflo-install update` do): a gateway still running on an older release loses
what it holds unspent. The licence key in the binary is unchanged. 0.12.22's tarballs are in this
repository's history at commit `c826485`.

### 0.12.22

**SMPP refusals refund what they charged.** The price of an SMPP submit is taken before the listener
checks its queue and its filters, and three refusals there -- queue full (`ESME_RMSGQFUL`), dropped by
a filter, and a filter that failed and refuses -- answered the client without giving it back. The
REST ingress always refunded the same three. On a staging gateway under overload, 170,712 queue-full
refusals had been charged this way. Each now refunds, once. If you run with `smsg.queue.capacity` set,
or with filters on an SMPP listener, earlier releases charged for these: they are the `cdr_rejected`
rows with reason `queueFull`, `filtered` or `filterFailed`.

**Postpaid accounts can send from the moment the gateway starts.** Their credit limits were first
read by the recharge poll, which sleeps first, so for up to `smsg.balance.recharge.poll.seconds`
(30 s) after every start a postpaid account with an empty balance was refused "insufficient credit".
The limits are now read at start, and by the first message if it arrives sooner.

**Prepaid credit blocks are no longer inflated by a burst.** Since 0.12.21 a message that finds its
account between credit blocks waits for the next; each waiting message also counted a miss, and a
burst doubled the next block's size hundreds of times, pinning every block at
`smsg.balance.block.max`. A miss now counts once per reservation.

**No migration** from 0.12.20 or 0.12.21; coming from 0.12.19 or earlier the 0.12.20 notes apply
(V1.94.0). The licence key in the binary is unchanged. 0.12.21's tarballs are in this repository's
history at commit `0711b7f`.

### 0.12.21

**A funded prepaid account no longer refuses part of a burst between credit blocks.** Credit is spent
from a block held in memory, and when an account spent it faster than the next block was reserved,
every message until that reservation landed was refused "insufficient credit" on an account that
could pay. Right after a restart that was most of an opening burst: the pre-warmed first block covers
20 messages, which lasts 40 ms at 500/s. Measured on a staging gateway after the 0.12.20 cutover: 51 of
10,000 refused, all in the first 125 ms, on an account holding thousands of messages' worth.

A message now waits for the reservation already in flight -- one shared by every waiting message, so
no extra database work -- and spends from it, at most 500 ms from its first miss. An account whose
last reservation found no money refuses at once for a second, so an empty account is never slowed.

Also the RabbitMQ client 5.37.0. **No migration** from 0.12.20; coming from 0.12.19 or earlier the
0.12.20 notes apply (V1.94.0). The licence key in the binary is unchanged. 0.12.20's tarballs are in
this repository's history at commit `56cb78d`.

### 0.12.20

**Recipients in the form each vendor asks for.** Recipients used to reach a vendor exactly as the
customer wrote them. A vendor's new **Convert recipient automatically** (`dest.addr.convert`, under
Detect sender type in Addressing) rewrites each number after routing, with libphonenumber, into the
form its Recipient type of number asks for: type 1, country code and number in digits
(`0412 345 678` → `61412345678`); type 2, national digits (`+61412345678` → `0412345678`), with a
number of another country sent internationally as type 1. **Recipient default country**
(`dest.addr.country`, beside Address range) is the ISO code for numbers written without one; blank
converts only numbers written with `+`.

Numbers already in the vendor's form are recognised without being parsed (0.04 µs each; 6 µs for one
that needs converting), so throughput is unaffected. A number that cannot be read goes unchanged and
is counted in `fireflo_smpp_client_recipient_unconverted_total`; nothing is refused. Only the
`submit_sm` changes: call records, receipts, pricing and a re-route to another vendor keep the number
as the customer sent it. Off by default; a change applies live.

**One migration, V1.94.0:** two `app_config_key` rows, no table changes. Coming from 0.12.18 or
earlier, the 0.12.19 notes apply too (V1.93.0). The licence key in the binary is unchanged. 0.12.19's
tarballs are in this repository's history at commit `c51ff86`.

### 0.12.19

**Queue housekeeping: archive and clean, instead of "no flush".** Until now the gateway refused to
flush a queue, so work waiting behind a dead vendor or a removed login could only be left there. It
can now be taken off a live queue -- a worker, routing, receipts or callbacks -- and every entry is
archived and ended the way a router drop ends it: the price refunded, a failed receipt queued for the
client, nothing silently discarded. `fireflo queue dump` shows what is waiting (held work is called
held), `fireflo queue archive` cleans with a dry run first and gives a summary, a list and a purge
that is reconciled against the summary before it deletes, `fireflo queue archived` reads it back, and
a spill file can be imported into the archive. `fireflo receipts repush` re-sends an SMPP login's
delivery receipts for a period, including messages that ended before any vendor attempt.
`smsg.queue.archive.retention.days` (default 0) leaves the archive alone until a purge is run by hand.

**Control panel 0.12.19.0:** Reports → Archives reads the queue archive; Archive & clean from the
Queues page and the vendor and listener pages; Re-send receipts… on an SMPP login, with a dry run,
progress and cancel; archive retention on the Gateway settings page. The panel pairs with schema 1.93.0.

**One migration, V1.93.0:** `queue_archive_batch`, `queue_archive` (partitioned by month) and
`queue_archive_summary`, and one registry row. Nothing existing is altered and the tables stay empty
until housekeeping is used. Coming from 0.12.16 or earlier, the 0.12.17 notes apply too (V1.92.0).
The licence key in the binary is unchanged. 0.12.18's tarballs are in this repository's history at
commit `0bef6dc`.

### 0.12.18

**The opening-burst fix, completed.** 0.12.17 made messages wait for an account's first credit
block instead of being refused, but right after a gateway restart that path never ran: the startup
pre-warm had already reserved a first block of the currency minimum -- usually one message -- so the
account counted as warm and the rest of its opening burst was still refused "insufficient credit"
while a proper block was fetched. Pre-warm now sizes each account's first block from its most recent
priced message (`smsg.balance.block.min.messages` of it, 20 by default) and leaves an account with no
priced message in the last 30 days cold, so its first burst reserves at the real price with every
concurrent message waiting for that one reservation. Measured on a staging gateway after a restart:
three messages sent together on a funded account, all three accepted, where 0.12.17 accepted one.

**No migration** from 0.12.17. Coming from 0.12.16 or earlier, the 0.12.17 notes apply (V1.92.0).
The licence key in the binary is unchanged. 0.12.17's tarballs are in this repository's history at
commit `22df7b4`.

### 0.12.17

**A fresh prepaid account no longer refuses its opening burst, and message text has a switch.**
When an account has no credit block in memory -- after a gateway restart, or its first send after a
top-up from zero -- the first message reserves one on a database round trip. Every message for the
same account that arrived during it used to be refused "insufficient credit" on a funded account;
they now wait for that one reservation (at most 4 seconds) and spend from it. A busy account that has
spent its block is unchanged: refused at once and refilled in the background. `smsg.cdr.body`
(whether call records keep message text: `off`, `excerpt` or `full`) is now a registered setting, so
any other value is refused when saved instead of being read as off, and the control panel has a
switch for it under **Gateway settings → Call records → Keep message text**. The installer carried by
the 0.12.16 re-cut is here too: `update` from 0.12.15 repairs the corrected V1.87.0 checksum itself.

**One migration, V1.92.0** (one registry row). It stops with the key named if an invalid
`smsg.cdr.body` value is already stored; set it to `off`, `excerpt` or `full` (or delete the row) and
run the update again. The licence key in the binary is unchanged. 0.12.16's tarballs are in this
repository's history at commit `61f6cec`.

### 0.12.16

**What the 2,000-message-a-second runs found, and a home page that no longer queries live.**
Gateway: a vendor that stops reading no longer parks the worker's sender for good (the socket write
is bounded by `window.offer.timeout.ms`; the dead session is dropped and re-dialled); a vendor
restart under load no longer deadlocks the router (retries are offered back to the router queue,
never blocked on); a bind's `system_type` selects a product **only when the login may name it** (its
own product or one on its allowed list, the same rule as the HTTP `product` field) — otherwise it is
ignored with a `bind.system_type.ignored` log line and the login's product applies. Installs that
relied on per-session product selection without an allow list must list those products on the
login. **Usage summaries move into the gateway**: `usage_hourly` (UTC hours, per account, product and
vendor) is maintained every minute and restated every 15 minutes for late receipts; the daily rollup
runs in-process at 00:15 billing time (`smsg.usage.hourly.*`, `smsg.usage.daily.schedule`;
`fireflo usage hourly --backfill DAYS` for history; the CLI rollup still works). Control panel: the
home page and the portal landing page are built in the background once a minute and served from the
snapshot with an **as of** time (`OVERVIEW_REFRESH_SECONDS`); a listener gets a confirmed **Restart**,
offered on the saved-but-needs-a-restart card too; **Ingress server** and **Vendor** in the Messages
search row; a product's login list pages; TLV catalogue notes behind an info button; rebuild default
routing no longer preselects a listener for inbound.

**These 0.12.16 tarballs were re-cut on the evening of 2026-10-15** with an installer that does the
repair below itself when it meets exactly that mismatch (the first cut, at commit `3ecdc03` of this
repository, stopped with a bare Flyway error and the service down). Gateway and panel are the same
builds. **One migration, V1.91.0**, additive (two tables, six registered keys). **Before migrating a
database that ran 0.12.15 with the first cut's installer, run `fireflo db repair` once:** 0.12.15's V1.87.0 was corrected in place so it no
longer fails where a second FireFlo schema shares the database, and its checksum changed; the
gateway does not validate checksums at start, so a running 0.12.15 is unaffected until its next
migrate. The licence key in the binary is unchanged. 0.12.15's tarballs are in this repository's
history at commit `8c0c142`.

### 0.12.15

**The hardening release from the 0.13 readiness review.** Gateway: a vendor that will not bind is
retried with backoff and jitter, and its keepalives no longer share the reconnect thread; a full
vendor window waits `window.offer.timeout.ms` and is counted; a client address refused repeatedly
is held back before its next bind (`srv.bind.backoff.enabled`); webhook retries when the broker is
absent are capped (`smsg.webhook.retry.pending.max`); call records are written on several lanes
(`smsg.cdr.writers`); configuration is republished only when it changed; the daily usage rollup
summarises finished days only; `/secure/send` and batch entries accept a `client_ref`, so a retried
send is one message; `/ops/health` and `/manage/status` carry `schema_version` and an `api`
capability map; batch callbacks to private addresses are refused like receipt webhooks
(`smsg.webhook.private.targets=allow` for a rig); the Swagger UI is served only when
`smsg.restapi.swagger.enabled` is on; the customer API is frozen as `api/openapi-customer.json`.
Panel: pairs on the schema version; dashboards and account usage read the daily summary with a
live tail for today; every configuration write is in the operator log; **writes are refused from a
browser whose address is not `AUTH_URL`** (a 403 naming both); a password change signs that user's
other browsers out; the licence page is admin-only; the SMPP test tool connects only to the
gateway's own hosts. Also carries 0.12.14, which was cut on 2026-10-15 but never published here:
a bound SMPP session follows its login's product; `TRUSTED_PROXY_HOPS=1` is needed behind a proxy;
message-text, number and outcome filters need a period of at most 92 days.

**Nine migrations, V1.82.0 to V1.90.0.** Dump the database first. V1.87.0 validates four CHECK
constraints over the call record tables and leaves one unvalidated with a notice if a historic row
is out of set; V1.89.0 builds a partial index on `cdr_submit`. Rollback is the 0.12.13 binary over
the restored dump. The licence key in the binary is unchanged. 0.12.13's tarballs are in this
repository's history at commit `6f84b25`.

### 0.12.13

**Apply now on the rule pages.** The gateway picks up a saved routing table, price or filter
within thirty seconds. The **Apply now** button the Servers and Vendors pages already had now
sits on Routing, Pricing and Filters, and under a table or scope you have just saved, so a
change is read at once. The gateway's reload answer says whether the configuration was adopted
at all: on a gateway whose licence is not current, the panel says "reloaded, but not adopted"
instead of claiming success.

**No migration** from 0.12.10, 0.12.11 or 0.12.12. The licence key in the binary is unchanged.
0.12.12's tarballs are in this repository's history at commit `77e1d67`.

### 0.12.12

**Two more tester fixes on top of 0.12.11**, which was cut earlier the same day. With
no account entered, the Pricing tab shows what **Everyone** charges by default instead
of no price at all. A Test clicked before the dialog had loaded the route tables no
longer costs a routing table as if it were a vendor.

**No migration** from 0.12.10 or 0.12.11. The licence key in the binary is unchanged.
0.12.11's tarballs are in this repository's history at commit `314d0a5`.

### 0.12.11

**The message tester asks what a real message asks.** A price rule saved under a
product prices only messages carrying that product -- and every real message carries
one: its login's, or the `system_type` it bound with. The tester sent whatever was in
its Product box, blank by default, so "everything else on *product*" showed no price,
and a routing rule or filter on product missed the same way. It now fills a blank
Product from the account's login, says on every tab which product it tested as, and
when there is no price says whether rules exist for another product and what to do
about it. The **Everyone** pricing scope warns when a rule's product is carried by no
login on any account, as account scopes already did.

If live messages are recorded with a blank price under such a rule, the cause is the
same: they carry no product, or another one. Set the product on the login under
Accounts, or have the customer bind with that `system_type`; past rows stay unrated.

**No migration** from 0.12.10. The licence key in the binary is unchanged. 0.12.10's
tarballs are in this repository's history at commit `5895370`.

### 0.12.10

**Eight database migrations, V1.74.0 to V1.81.0.** Seven are additive. **V1.80.0 is
not: it turns `cdr_submit`, `cdr_final`, `cdr_interim` and `cdr_event` into tables
partitioned by month**, attaching the existing rows as the first partition without
copying them but building two indexes over all of them while the gateway is stopped
(seconds on a small install, up to an hour on a hundred million rows). The 0.12.9
binary cannot run against the result -- its INSERT names a unique key that no longer
exists -- so **rollback after this upgrade is a database restore.** `fireflo-install
update` says so before migrating and asks; take the backup it suggests. The licence
key in the binary is unchanged.

**Retention is a partition drop.** `fireflo usage purge` drops whole months (after the
same rollup check as before); `cdr_interim` and `cdr_event` are dropped by month on
their own windows (`smsg.cdr.event.retention.days`, 90); `cdr_rejected` is pruned by
age (`smsg.cdr.rejected.retention.days`, 90). The gateway creates the coming months'
partitions itself.

**Customer passwords encrypted at rest.** With `FIREFLO_SECRETS_KEY` set in the
gateway's `fireflo.env` *and* the control panel's `panel.env` (the same value), every
password either writes is stored as `enc:v1:...` (AES-256-GCM). A fresh install gets
a key from the installer; an upgraded install keeps plaintext until you set the key on
both, restart both, and run `fireflo db secrets seal` once. `fireflo db secrets
status|seal|open`; `FIREFLO_SECRETS_KEY_NEXT` for rotation. The API key of an HTTP login
is its name and stays readable.

**Listener and router.** `srv.out.threads` now runs as many out threads as it says
(it ran one), over a bounded queue (`srv.out.queue`, 100000); a receipt waits for a
slot in the customer's receive window for `conf.window.wait.ms` (2000) rather than the
30 s response timeout, so one full window no longer holds everyone else's responses;
the segments of one receipt go out as one task. The router defaults to two threads
and offers a message to its target for 250 ms before re-queueing it with the backoff
(`fireflo_routing_target_full_total`). The call record writer never blocks the message
path (200 ms, then spill or count; queue default 100000). A receipt's broker publish
is confirmed on a hand-off thread, never the vendor's I/O thread. The receipt store no
longer commits per receipt and sweeps in bounded passes every ten minutes.

**Also:** a prepaid block names the gateway holding it (`account_balance.reserved_by`,
`FIREFLO_INSTANCE_ID`) and is reclaimed by that gateway's next start; the inbound-message
webhook carries `messageId` (`message_id` in form encoding); name-keyed foreign keys
cascade on update and rule positions are deferrable, so the panel reorders in place;
`bind_hold` is `app_bind_hold`; `app_config` refuses new `outSms.instance.*` rows (the
worker's own table holds them); the address allow list is checked before the password on
SMPP and REST, the SMPP compare is constant-time, and four ops routes carry a body limit.

**Control panel 0.12.10.0**, included at `panel/`: writes and reads sealed passwords
(the installer copies the key from the gateway's `fireflo.env`); reorders rules under
the deferred constraint; the two new retention settings and the two new listener
settings on their forms.

### 0.12.9

**No database migration and no new setting.** Upgrading from 0.12.8 swaps the
binary and the panel. The licence key in the binary is unchanged.

**A receipt no routing rule placed goes back to its listener.** A delivery
receipt has exactly one correct destination: the SMPP listener its message
arrived on. Until now a receipt with no matching rule was retried twenty times
and dropped, so a customer on a listener added after the routing table was
built never got a receipt. The gateway now returns such a receipt to its own
listener, after the rules and never instead of them, so a receipt rule you wrote
on purpose still wins. It logs `routing.dlr.builtin listener=…` at most every ten
minutes per listener, so a table missing a rule is still visible. Inbound
messages from vendors are never sent back where they came from.

**Control panel 0.12.9.0**, included at `panel/`:
- **Receipt rules are created with each listener and locked.** Every SMPP
  listener gets a rule in the `default` table returning its receipts to it,
  written together with the listener; deleting the listener removes it. The
  rules show as **System** with a lock: they can be moved, but not edited,
  switched off or deleted. Outbound and inbound rules stay editable.
- **Existing listeners are repaired by saving them once** (Servers → the
  listener → Edit → Save). On a gateway with two or more listeners that also
  narrows the original receipt rule, which took every listener's receipts, to
  its own listener. Saving the `default` table does the same.
- **The receipt check on Routing → Start here** no longer reports a correct
  table as sending receipts to the wrong listener, or to none. It read the
  rule below the one that matched.

### 0.12.8

**These 0.12.8 tarballs were re-cut on 2026-10-14 with control panel 0.12.8.2;
the gateway in them is byte for byte the one first published.** The first
tarballs (x86-64 SHA-256 `91d513de…20a7`, ARM `6ad2d6cc…1d45`, panel 0.12.8.1 at
`2ec6e83`) are in this repository's history at commit `d1e0f81`. 0.12.8.2 changes
one thing:

- **A Fix link on the TLV-stamping warning.** When an approved sender ID or
  template carries a TLV a listener requires, and that listener has
  `whitelist.tlvs.mode` off, the warning now says **Fix on <listener>**. It
  opens that listener's edit form with the TLVs section expanded, where
  **Stamp approved TLVs** is set. On the account's Approvals tab and on the
  Headers and Templates pages.

**One database migration, `V1.73.0`, and it is additive:** a new, empty table,
`bind_hold`, for the hold-outs below. No existing data changes and no setting is
added. `fireflo-install update` migrates before starting the new binary; by hand,
run `fireflo db migrate` first. The licence key in the binary is unchanged.

**Force disconnect, and holding a client out.** Drop every SMPP session of an
IP address, an account or a login — matched exactly, never by prefix — on every
listener or one, with a preview of who would go first. Optionally refuse that
target's binds afterwards for 15 minutes, 1 hour, 24 hours or until lifted.
- Holds are kept in `bind_hold` and re-read by every node at most every ten
  seconds at bind time; the gateway fails open if it cannot read them.
- A held-out bind is refused and logged with `reason=heldOut`, which the
  fail2ban filter now ignores, so a client retrying against a hold is never
  turned into a host-wide ban. Installs with fail2ban pick up the new filter on
  their next `fireflo-install fail2ban`.
- Ops endpoints: `GET /ops/sessions/match` (read), `POST /ops/sessions/disconnect`
  (admin, `hold=SECONDS|forever`), `GET /ops/bind-holds` (read) and
  `DELETE /ops/bind-holds/{id}` (admin).

**`fireflo-install smppsim --tenant NAME [--account ID]`** adds SMPPSim to an
install that already exists: the simulator as its own service, the vendor
`smppsim`, a catch-all to it in `MESSAGE` **only when `MESSAGE` has none**, a test
login `fireflo-selftest`, a gateway restart, then `fireflo selftest`. Database
mode, safe to run again, and it refuses an SMPPSim folder it did not make. The
database half is the new `fireflo smppsim-setup`.

**Control panel 0.12.8.1**, included at `panel/`:
- **Force disconnect** on a server's page, on a connected login's live sessions,
  and on **Security**, which also lists the holds in force with **Lift**.
  Disabling a login now drops its sessions in one gateway call.
- **Receipts with two or more listeners.** The receipt rule bootstrap writes
  sends type 18 to the one listener with no listener condition, so after a
  second listener was added it took every receipt and clients on the second never
  got their DLRs — while **Rebuild default routing** reported nothing to fix. It
  now narrows that rule in place to its own listener and adds one for each
  listener still without, and the routing page flags the condition. **After
  upgrading a gateway with more than one SMPP listener, open Routing and run
  Rebuild default routing once.**

### 0.12.7

**No database migration.** From 0.12.6 this is a binary swap; `fireflo-install
update` handles it. The licence key in the binary is unchanged, so no new
licence is needed.

**SMPPSim, optionally.** The tarball now carries SMPPSim at `smppsim/` —
third-party software under the GPL-2, with its licence and complete source
beside it, and not part of FireFlo or its licence. `fireflo-install install
--bootstrap --with-smppsim` (off by default, never implied by `--yes`):
- installs the distribution's Java runtime for SMPPSim alone — the gateway
  still needs none;
- runs SMPPSim beside the gateway as its own unit, `<service>-smppsim`, with
  every message delivered, on ports 7775 and 7788 (`--smppsim-port`,
  `--smppsim-console-port`), outside the listener band and never opened in
  the firewall;
- has bootstrap add it as the vendor `smppsim` with a catch-all in `MESSAGE`,
  a cost on it (`--vendor-cost`, asked, default 0.0050) and prepaid credit on
  the first account (`--opening-balance`, asked, default 10.00);
- ends by running `fireflo selftest`.

SMPPSim accepts everything and invents delivery receipts: it is for trying
FireFlo out, never for customer traffic.

**`fireflo selftest`** sends one real message and reports PASS, FAIL or SKIP for
each of: accepted, routed (to which vendor, by which rule), billed (price, cost,
margin), delivered, and — with prepaid on — debited by exactly the price. The
debit is read from the account's own balance before and after, so it needs no
admin token and works on an unlicensed gateway. It signs in with
`FIREFLO_SEND_LOGIN`/`FIREFLO_SEND_PASSWORD`, or the login bootstrap saved.
Exit 0 when nothing failed, 1 when something did.

**`fireflo bootstrap`** gains `--vendor` (with `--vendor-host`, `--vendor-port`,
`--vendor-system-id`, `--vendor-password-file`), `--vendor-cost`,
`--opening-balance` and `--login-file`, which adds an HTTP login `fireflo-http`
on the same account and saves it owner-only for the self-test.

**Billed units and cost units are recorded on every message**, priced or not.
A gateway with no rate rules left both blank, and one whose rules matched
nothing dropped them with the price. Price, cost, the rates and margin status
are unchanged, nothing is charged without a price, and existing call records are
not touched.

**Control panel 0.12.7.0**, included at `panel/`: `update` no longer re-asks for
the public URL when `panel.env` already holds a public one; it asks only when
it is missing or a localhost value.

### 0.12.6

**0.12.6 carries two database migrations.**
- **`V1.71.0`** registers two REST settings, `smsg.restapi.token.ttl` (default
  3600 seconds) and `smsg.restapi.token.plain.http.allowed` (off). No data changes.
- **`V1.72.0`** rewrites prefix-list conditions. The control panel's "Any of these
  prefixes" saved a destination condition as `matches ^(\+91|91)`; the gateway's
  `matches` is a whole-value match, so it only ever matched a number that *was*
  `91` or `+91`, and every real number missed. The migration rewrites exactly
  that shape — in routing, filter and price conditions — to the new
  `startsWithAny` operator (`+91,91`). Hand-written regular expressions are left
  alone. **Rules that never matched start matching as written**: read your
  prefix rules before upgrading if any of them was worked around.

`fireflo-install update` migrates before starting the new binary; by hand, run
`fireflo db migrate` first. The licence key in the binary is unchanged, so no new
licence is needed.

**`startsWithAny`.** A comma-separated list of literal prefixes, matched with one
lookup per distinct prefix length rather than a regular expression. Numbers are
compared exactly as given: list `91` and `+91` if both arrive.

**Testing a message.** Three read-only endpoints on the read token answer what
the gateway would do with a message nobody sends: `GET /ops/rating/explain`
(the account's price, the vendor's cost and the margin), `GET /ops/filters/test`
(every named filter, and the rules that use it), and `/ops/routing/explain`,
which now takes `account`.

**Sessions per login.** `GET /ops/sessions/summary?system_id=a,b` reports each
login's sessions by bind type on every listener and per listener, with hosts
and the oldest bind. It matches system IDs exactly.

**A management API**, off unless `FIREFLO_MANAGEMENT_TOKEN` is set (at least 32
characters): HMAC-signed requests that provision an account with an HTTP login
and a prepaid balance, top it up idempotently, and issue short-lived bearer
tokens. Requests must arrive over TLS or loopback, or over plain HTTP from an
allow-listed address when that is switched on. Database configuration only.

**Control panel 0.12.6.1**, included at `panel/`, pairs with it.
- **Test a message** on the Routing, Pricing and Filters pages: which rule routes
  it, what the account pays and the vendor costs, which filters it meets — and,
  when nothing matches, the rule to create, pre-filled.
- **Logins**: an SMPP login shows Connected or Not connected, its sessions by TX,
  RX and TRX against its own limits, where they come from, and how long they
  have been bound. Every ten seconds.
- **Routing**: a table nothing routes to says so on its page, in the rail and in
  the tester. The rail uses the same cards as Pricing.
- **Products** is two columns: every product on the left, the open one on the
  right with a pricing summary and the logins that select it. **Pricing** can be
  narrowed to one product from a picker on its rail; the separate product
  pricing page is gone.
- "Any of these prefixes" now saves `startsWithAny`.

### 0.12.5

**Re-cut with control panel 0.12.5.1.** The gateway binary is the same as the
first 0.12.5 tarball, byte for byte, so a gateway already on 0.12.5 needs
nothing. Only the panel changed; upgrade it with its own installer.

**Control panel 0.12.5.1**: the Queues page's "Where messages are waiting" card
keeps its shape however many vendors there are. Only queues with messages
waiting or retries scheduled are listed, busiest first; the idle ones fold into
one line ("+ 15 idle vendors, 2 idle servers · show") that opens in place, in a
list that scrolls rather than stretching the card. Each row is one line, and the
arrows stay level with the Broker and Router tiles.

**0.12.5 carries two database migrations, and both are additive.**
- **`V1.69.0`** adds a table, `tps_peak`: the highest throughput each vendor and
  listener has reached, and every vendor and every listener together, with when.
  It starts empty and fills from the first SMPP traffic measured after the upgrade.
- **`V1.70.0`** registers one setting, `smsg.smpp.whitelist.first.bind`, off by
  default. No data changes.

`fireflo-install update` migrates before starting the new binary; by hand, run
`fireflo db migrate` first. The licence key in the binary is unchanged, so no new
licence is needed.

**Peak throughput is kept.** The gateway records the highest rate it measures,
over the same 5-second window as the live figure, and keeps it across restarts;
on a cluster the highest node's figure is kept. `/ops/health` reports it per
worker (`tps_peak`) and in total (`tps_peaks`), and the new admin endpoint
`DELETE /ops/tps-peaks` resets one or all. SMPP only, as the live figure is.

**An SMPP login can be locked to its first address.** With
`smsg.smpp.whitelist.first.bind` on, the first successful bind by a login that
has no allowed addresses saves that exact address as its only one, and binds
from anywhere else are refused. The first node to save wins on a cluster, and the
bind fails open if the database cannot be reached. **Switching it on applies to
existing logins at their next bind**: check first that no customer binds one
login from more than one address. Needs logins kept in the database.

**Control panel 0.12.5.0**, included at `panel/`, pairs with it.
- **Vendors and Servers**: a small "Peak 1,436/s · 13 Oct, 02:58" line on each
  card, on the Throughput card for the total, and on each vendor's and server's
  page, where an admin can reset it.
- **Messages**: a message the carrier has acknowledged with a progress receipt
  (ACCEPTD, BUFFRED) now reads "Accepted by the carrier" instead of "Awaiting
  receipt" — it used to look as if the list and the message's own page
  disagreed. The list has a **Refresh**, and the ingress server shows its port.
  The customer portal's Messages list gets the same badge.
- **Gateway settings**: the new lock is under **SMPP logins**.

### 0.12.4

**0.12.4 carries one database migration, `V1.68.0`, and it is additive.** It adds
one nullable column, `usage_daily.mt_parts`: how many SMS parts each day's
messages were sent as, per account and product. A three-part message counts
three; a message every vendor refused counts none. Existing rows get NULL,
meaning "not counted", not zero. No data changes and no configuration keys move.
`fireflo-install update` migrates before starting the new binary; by hand, run
`fireflo db migrate` first. The licence key in the binary is unchanged, so no new
licence is needed.

**After upgrading, fill the part counts for past days:**

```
fireflo usage rollup --catch-up
```

It fills every day whose call records are still kept, and a re-run never lowers
a count. Days already purged stay uncounted, and the control panel says how
many there are rather than counting them as zero. Nothing on the message path
changes.

**Control panel 0.12.4.0**, included at `panel/`, pairs with it.
- **Billing tab, rebuilt.** One card across the top: the balance and the
  actions that change it on the left, and MT parts sent on the right (lifetime,
  this month, last 7 days, today so far). Beneath it, MT parts per day over 7,
  30 or 90 days with a table by product (messages, parts, charged), beside the
  reconciliation, and the ledger across the full width. Resellers see the same
  for their own accounts.
- **Amounts without trailing zeros.** Every amount on screen keeps at least one
  decimal place and drops the zeros after it: `0.0000` reads `0.0`, `0.0100`
  reads `0.01`, a `0.0450` rate reads `0.045`. Display only: the API, the
  database and CSV exports keep all four places.
- Against a gateway older than 0.12.4 the panel still works; days already
  summarised then read as not counted.

### 0.12.3

**Re-cut with control panel 0.12.3.1.** The gateway binary is the same as the
first 0.12.3 tarball, byte for byte, so a gateway already on 0.12.3 needs
nothing. Only the panel changed. Upgrade it with its own installer.

**Control panel 0.12.3.1**, a look-and-feel release:
- **Sign-in pages, rebuilt.**
  - The operator sign-in is one card, with show/hide on the password and a
    proper Remember me checkbox.
  - The customer portal's sign-in is one wide card. Its left side says what the
    portal is for, and on a white-labelled portal it names no platform.
  - The password now has show/hide there too, and only "Email me a sign-in
    link" is a link.
- **One type scale across the panel.**
  - Tailwind's default font.
  - Body text and every control at 14px, labels and help at 12px, card titles at
    16px and page titles at 24px.
  - Every textarea matches the inputs.
  - Numbers are no longer set in monospace, and no monospace text is smaller
    than 12px.
- **Page sidebars are cards** on Pricing, Gateway, Error codes and Filters.
- **Refused:** the Why column's message opens in a popover, so each refusal is
  one line.
- **Accounts:** the stat cards and the id card are the same height, with bigger
  counts.
- **Dark mode:** browser-drawn controls (checkboxes, select menus, scrollbars)
  are dark too.

**0.12.3 carries one database migration, `V1.67.0`, and it changes no data.** It
updates one row of `app_config_key`: `smsg.queue.provider` now takes only
`memory` or `rabbitmq`, checked when it is written, and is marked as set on the
control panel's Queues page. **It refuses, and changes nothing, if
`smsg.queue.provider` already holds anything else** (the gateway reads such a
value as `memory` today): correct or remove it, then migrate again.
`fireflo-install update` migrates before starting the new binary; by hand, run
`fireflo db migrate` first. The licence key in the binary is unchanged, so no
new licence is needed.

**Testing a message broker from the gateway.** A new admin endpoint,
`POST /ops/queue/test`, takes an AMQP address and a queue name, connects once on
a connection of its own, and reports each step: TCP, login, virtual host, queue.
It changes nothing on the broker, and a queue that does not exist yet is
reported rather than failed, because the gateway creates it when it starts.

**The gateway says when a saved broker is waiting for a restart.** The broker
is connected once, at startup. `/ops/queues` now carries
`broker_restart_needed` when the saved provider, address, queue, prefetch or
channels differ from the ones in force. Health now reports the broker the
gateway is actually running on. Before, a broker that had been saved but not
yet restarted into could show as not answering.

**Control panel 0.12.3.0**, included at `panel/`, pairs with it.
- **Queues: edit and test the message broker** (admins). Choose in-process or
  RabbitMQ and set host, port, virtual host, queue, user, password, TLS and
  tuning. **Test connection** runs from the gateway with what is in the form,
  saved or not. The password never reaches the browser. A save says "restart
  the gateway to apply" until the gateway runs on it. With no broker in use,
  the Broker tile opens the same card to set one up.
- **Servers:** a listener has an optional **Public IP** beside its port, the
  address customers are told in connection instructions. The gateway does not
  bind to it. **Listener enabled** sits under the port.
- **Connection instructions** name one listener, at its Public IP, then its own
  address, then the panel's `FIREFLO_PUBLIC_HOST`. The password is masked in
  the preview and sent in full in the email and the copy.
- **Logins: an SMPP client test tool** (admins) binds as a login from the panel,
  sends a test message and shows the receipts.
- **Accounts:** counts, and "Open an account by id", above the table. **Portal
  access** uses the account's email instead of asking for another.
- **Messages:** the server a message arrived on, **Ingress server**, is shown
  by default.

### 0.12.2

**0.12.2 carries one database migration, `V1.66.0`, and it is additive.** It adds
five empty columns to `app_credential` for per-login limits; every existing login
gets none, which is today's behaviour. **The gateway reads those columns, so the
database must be migrated before the new binary starts** — `fireflo-install
update` does it in that order; by hand, run `fireflo db migrate` first. The
licence key in the binary is unchanged, so no new licence is needed.

**Per-login limits for SMPP logins.** Each login may now have its own:
- **sessions** in total, of any bind type, on one listener;
- **transmitter, receiver and transceiver** sessions, each separately;
- **TPS** across all of its sessions on one listener.

Empty means none of its own. They only narrow: the account's connection limit
and TPS still apply on top, so a login can be held below its account but never
lifted above it. A bind past a session limit is refused as too many sessions
(`ESME_RMAXCONSPERUSER`); a message past the TPS is answered throttled. A
changed TPS reaches the login's sessions from their next bind. In file mode they
are a `limits:` block in `credentials.yml`.

**Also in the gateway.**
- **The live SMPP watch downloads as a pcap** for Wireshark
  (`GET /ops/watches/{id}/watch.pcap`, admin token), each client connection its
  own TCP stream. Like a capture's, the TCP framing is rebuilt around the PDUs:
  it shows exactly what SMPP was said, not how the network carried it.

**Control panel 0.12.2.0**, included at `panel/`, pairs with it.
- **Logins:** session, bind-type and TPS limits in a login's form, and its
  address list, are edited only with **Advanced** on; with it off, one line says
  what is in force. The login card shows a login's limits when it has any. The
  portal never sets them.
- **Security, redesigned around who is attacking:**
  - one range for the whole page: 24 hours, 7 days or 30 days;
  - refused logins grouped by address (attempts, the names tried, last seen,
    blocked or not), with **Watch** and **Unban**, or every attempt; both page by
    25;
  - refusals over time, stacked by surface;
  - a rail with what is blocked, sign-ins for the same range, and the live watch.
- **The live SMPP watch** runs in a window that fits the screen, with **Download
  pcap**.

0.12.2 also carries control panel 0.12.1.1's installer change below: `update`
asks for the public URL.

### 0.12.1

**0.12.1 carries one database migration, `V1.65.0`, and it is additive.** It
lets the operator access log keep one more kind of event, `account_updated`,
which the control panel now writes when an operator changes an account. It
cannot refuse on existing data. `fireflo-install update` runs it before
starting the new binary; by hand it is `fireflo db migrate`. The licence key in
the binary is unchanged, so no new licence is needed.

**Sender IDs, templates and products now match whatever their case.** This
fixes messages being refused as "not an approved sender ID" when the sender ID
was approved.
- **The cause.** Approved sender IDs are filed by account *and product*, and
  the product a session sends under is its SMPP bind's `system_type`, or the
  product a REST call names. That was compared exactly, so a session bound as
  `otp` found nothing approved under the product `OTP`, and every message was
  refused. The sender ID itself already matched in any case.
- **Now.**
  - A `system_type` or REST product in any case is the catalogue's product of
    that name, and is recorded under its catalogue spelling in CDRs and rates.
  - A login allowed a product may name it in any case.
  - An approval given to one login applies to that login in any case.
  - Template wording matches in any case: `Your OTP is {#num#}` accepts
    `YOUR OTP IS 1234`. `{#num#}` still accepts only digits.
- **A refusal now names the product it looked under**, for example `'MYBANK' is
  not an approved sender ID for this account under product 'otp'`, so the next
  mismatch can be read off the error.
- Nothing is rewritten: stored sender IDs, templates and product names keep
  their case. Only the comparison changes.

**Also in the gateway.**
- **A live SMPP watch.** Watch one client address on a listener port and see
  every PDU it sends and is sent, as it happens, including binds refused for a
  wrong password, an address not allowed or a limit, which never become
  sessions. Admin token; at most three watches, 30 minutes each; starting one is
  logged.
- **A vendor's connection test reports each step:** name lookup, TCP connect,
  bind, three timed `enquire_link`s and unbind. A vendor that is already bound
  is no longer refused; its live sessions are timed instead of a second bind
  being opened.
- **Bash preprocessors.** `.sh` files run with `bash` (`smsg.preprocessor.bash`
  to change it), with a helper and a do-not-disturb example in
  `conf.example/preprocessors/`.
- **Fixed: a vendor could stop for good after its SMSC restarted under a large
  backlog.** A failed send that was retried while the vendor's queue was full
  could block the connection's own network thread, and reconnects never
  completed until the gateway was restarted. A retry now never waits for room.
- **Faster RabbitMQ intake.** Publisher confirms are shared and batched, acks
  are batched, and batch submissions skip a second broker hop. Measured locally
  on 20,000-message batches: acceptance went from about 800 to about 5,600
  messages a second, with RabbitMQ using a third of the CPU and nothing lost.

**Control panel 0.12.1.0**, included at `panel/`, pairs with it.
- **Portal passwords that show and work.**
  - An account's Settings tab has a **Portal access** card listing every
    portal login, how it signs in, its last sign-in, and set, change or remove
    password and on or off.
  - The **portal signs in with a password**, with the emailed link one click
    away, and ten failed attempts in a quarter of an hour lock that address out
    from that IP.
  - Customers set or change their own password at **Password** in the portal
    header.
- **Account activity.** An account's Settings tab shows portal sign-ins,
  changes made by operators and customers, and money movements, newest first.
  Changes to an account's name, notes, address or hierarchy are recorded with
  before and after.
- **Security** is two columns: refusals and bans on the left, the live SMPP
  watch on the right. **Fixed: the gateway's refused SMPP and REST logins never
  reached this page**; only the panel's and portal's did.
- **Vendors** show the connection test's steps. **Servers** keep Edit, Disable,
  Stop sending and Hold in the card's footer. The preprocessor workbench edits
  and checks bash.
- The footer reads **FireFlo by RemotIQ**.

**This 0.12.1 tarball was re-cut on 2026-10-13 with control panel 0.12.1.1; the
gateway binary in it is byte for byte the one first published.** The first
0.12.1 tarball (SHA-256 `bbb77565…50d054`, panel 0.12.1.0 at `d9e89db`) is in
this repository's history at commit `e01f068`. 0.12.1.1 changes the panel
installer and nothing else:

- **`fireflo-panel-install update` asks for the public URL (`AUTH_URL`).** A
  panel installed without `--public-url`, or with the development value
  `http://localhost:3000`, sends every sign-out to localhost and cannot finish a
  sign-in behind a proxy, and until now no update ever changed it. `update` now
  shows the current value, offers it back unless it is localhost (then the
  portal's `MIS_PANEL_BASE_URL`), refuses one with a path, and writes it before
  restarting. `--public-url https://…` answers without asking; `--yes` keeps
  what is there and warns when it is localhost or missing.
- **Already installed?** Nothing else changed, so you can fix it by hand
  instead: set `AUTH_URL=https://<the panel's host>` (no path, no trailing
  slash) in the panel's `panel.env`, remove any `AUTH_URL=http://localhost:3000`
  or `NEXTAUTH_URL` line, and restart the panel's service.

### 0.12.0

**0.12.0 carries three database migrations, `V1.62.0` to `V1.64.0`, and all
three are additive.**
- **`V1.62.0`** creates the empty table `app_preprocessor`. It also adds a column
  to routing rules that stays empty until a rule sends to a preprocessor.
- **`V1.63.0`** lets the operator access log keep three more kinds of event.
  One of them, `connection_instructions_sent`, the panel has written since it
  began mailing connection details, and until now the database refused it.
- **`V1.64.0`** registers the two new settings.

None of them can refuse on existing data, and nothing that routes today
changes. `fireflo-install update` runs them before starting the new binary;
by hand it is `fireflo db migrate`. **From 0.11.4 or earlier the update also
runs 0.11.5's nine migrations**, which can refuse. Read the 0.11.5 notes below
and take a backup first. All thirteen from 0.11.3's schema, `V1.52.0` to
`V1.64.0`, were rehearsed together on a copy of a real trial database: they
applied in two seconds with nothing refused.

**Preprocessors: your own program, for the messages a routing rule selects.**
A preprocessor is a Python, Java or other program the gateway keeps running
beside itself.
- **Wiring it in.** A routing rule hands messages to one by naming it with a
  leading `@` as its target, and only the messages that rule matches reach it.
- **What it can answer.**
  - carry on;
  - change fields (`from`, `to`, `product`, `field1`–`field10`);
  - attach or remove TLVs (vendor tags `0x1400`–`0x3FFF`; a vendor sends a tag
    only when its `registered.tlvs.submit` names it);
  - send to a specific vendor or table;
  - refuse, which is refunded and sends a failure receipt;
  - drop;
  - try again later.

  Routing then carries on below the rule.
- **It doesn't slow routing down.**
  - The router hands a message over without waiting, and the answer comes back
    through the router queue.
  - A program that is slow, full, not yet started or crashed gives its messages
    a fallback you choose. The default is to carry on as if the rule were not
    there.
  - A crashed program is restarted.
  - A program that is replaced finishes what it holds first.
  - Measured: a rule that doesn't select a message adds about 34 ns to routing
    it, and a Python answer takes 0.05–0.08 ms.
- **Where the program lives.** In `/etc/fireflo/preprocessors`
  (`smsg.preprocessor.dir`). Each file must be owned by root or the gateway's
  user and writable only by its owner.
  - `.py` runs with `python3`.
  - `.java` runs as a single-file program with `java`.
  - `.jar` runs with `java -jar`.
  - Anything else must be executable.

  The host needs that interpreter; the gateway itself still needs no Java.
- **Setting one up.**
  - **File mode:** a `[preprocessor:name]` block in `routingTable.conf`.
  - **Database mode:** the panel's Preprocessors page.

  The database only ever names a file and never holds code.
- **Off until switched on.** "Run preprocessors" under Gateway settings
  (`smsg.preprocessor.enabled`). Upgrading changes nothing until you turn it on.
- **Getting started.** `conf.example/preprocessors/` has a Python helper and
  two samples:
  - a do-not-disturb list in Python;
  - a sender rewrite in Java.

  The helper's notes show the TLV answer.

  `docs/05-routing-engine.md` has the guide.

**Control panel 0.12.0.0**, included at `panel/`, pairs with it.
- **A Preprocessors page** under Configuration. It shows each preprocessor's
  live state and its answer times, and the gateway's own reason when one
  cannot run.
- **A workbench for each one:**
  - the code in an editor on the left;
  - **Check**, which parses it with the gateway host's own `python3` or `javac`
    and marks the line at fault;
  - **Test**, which runs the draft against sample messages in a throwaway copy,
    never the live one;
  - **Save and run**, live within five seconds, with running copies finishing
    what they hold first;
  - **History**, with restore.
- **Who can change code.**
  - Saving and testing need an admin.
  - Every save is kept on the gateway host and recorded in the access log.
  - "Edit preprocessor code from the panel" (`smsg.preprocessor.editable`)
    turns editing off, for hosts where code is deployed by hand.
- **Routing.** Preprocessors are offered as rule targets, and rules that send
  to one read as "hands matching messages to …, then carries on".
- **Queues** shows what each preprocessor holds.
- **New grant:** `SELECT, INSERT, UPDATE, DELETE ON app_preprocessor` for the
  panel's database role. The panel README lists it.

0.12.0 also carries everything in control panel 0.11.5.1 to 0.11.5.3 below.

### 0.11.5

**0.11.5 CARRIES NINE DATABASE MIGRATIONS, `V1.53.0` to `V1.61.0`.** They
normalise the configuration tables: the references that were plain text become
foreign keys, so a mistyped account, product, vendor or route can no longer be
saved. `fireflo-install update` runs them before it starts the new binary; on a
gateway you migrate by hand it is `fireflo db migrate`.

**Take a backup first, and ideally rehearse on a copy.** Every migration that
could meet data it cannot keep **refuses** instead of rewriting it: the
upgrade stops, the old binary keeps running, and the message lists each row in
the way and what to do about it. Nothing is changed silently. They refuse on:

- account ids with leading or trailing spaces, or blank;
- product names with leading or trailing spaces;
- rows still in the legacy `app_route` or `app_rate` tables (the message prints
  the export and `fireflo import routing|rates` commands that move them);
- a vendor group member that names no vendor;
- a routing rule whose target is not a route table, a vendor group or a vendor;
- a rate rule or balance in a currency other than the platform's;
- a setting whose stored value its key does not accept.

What they do to an existing database:

- **Accounts and products are real rows.** Every account id and product named
  in the configuration tables gets an `app_account` or `app_product` row
  (products added this way are created disabled, so pricing is unchanged).
  Account and product references become foreign keys `ON DELETE RESTRICT`;
  deleting an account or product that is still in use is refused, and the
  panel says what is in the way.
- **A login's allowed products** move from an array to the table
  `app_credential_product`, kept in step by a trigger.
- **Routing rules point at typed targets** (`target_table`, `target_group` or
  `target_worker`, exactly one), and a vendor group member must name a vendor.
- **Who requested and reviewed** a sender ID or template, and who last changed
  a TLV, is also recorded as an `app_user` id.
- **One platform currency.** A rate rule or balance that restates it is stored
  as "the platform currency", and changing it while rules name another is
  refused.
- **`app_config_key`** lists every configuration key: its type, its allowed
  values, whether it is a secret, and whether the panel may edit it. The
  gateway and the panel both read it, and a value the key does not accept is
  refused when it is written.
- **The legacy tables `app_route` and `app_rate` are dropped**, and duplicate
  indexes are replaced by the ones the foreign keys need.

Call records (`cdr_*`) and `usage_daily` are not touched.

**Rolling the gateway back to 0.11.4 is not supported after migrating.** 0.11.4
still reads the dropped legacy tables. Restore the backup instead.

**THE PANEL'S DATABASE ROLE NEEDS ONE NEW GRANT.** Without it the panel cannot
read `app_config_key`, falls back to its built-in key list, and logs a warning:

```
GRANT SELECT ON app_config_key TO fireflo_rw;
```

A role built from an older copy of the grant block may also lack the vendor
group tables, without which Routing → Vendor groups cannot open:

```
GRANT SELECT, INSERT, UPDATE, DELETE ON app_route_group, app_route_group_member TO fireflo_rw;
```

(with your panel role in place of `fireflo_rw`; the full block is in
`panel/README.md`).

**Fixed: the native gateway discarded every message sent through RabbitMQ.**
With `smsg.queue.provider=rabbitmq`, every native build since 0.4.1 accepted
REST messages with a 200 and then dropped them on the way off the broker,
logging `Discarding an undecodable AMQP payload`. Nothing reached a vendor or
the call records. The in-memory queue was not affected. If you run RabbitMQ on
a native build, upgrade.

**Usage figures count messages, not vendor attempts.** A message that failed
over to a second vendor was counted, and its price summed, once per attempt in
the daily rollup and on several panel pages. Each message is now counted once,
with its money once.

**Control panel 0.11.5.0:**

- **Send connection instructions** on every login card mails the customer the
  server address, the chosen SMPP listeners' ports, their system ID and
  password (untick to leave it out), their allowed IP addresses and their
  limits. HTTP logins get the API address and a curl example. The preview masks
  the password, each send is in the operator audit log, and without SMTP the
  dialog offers Copy text instead. Two settings prefill the address:
  `FIREFLO_PUBLIC_HOST` (new) and `GATEWAY_API_URL` (existing).
- **Deleting something still in use is refused in a sentence** naming what
  uses it: an account, a product, a vendor, a route table or a vendor group.
- **Every sample env file is complete.** `conf.example/fireflo.env`,
  `panel/conf.example/panel.env` and `panel/.env.local.example` now list every
  setting the gateway and panel read, commented out at its default. Existing
  env files keep working unchanged.

The licence key compiled into the binary is unchanged, so no install upgrading
to 0.11.5 needs a new licence. The REST panel is still not in this tarball; the
0.11.3 notes below say where it is.

**This 0.11.5 tarball was re-cut on 2026-10-12 with control panel 0.11.5.1;
the gateway binary in it is byte for byte the one first published.** The first
0.11.5 tarball (SHA-256 `b5c5e097…7d26ea63`, panel 0.11.5.0 at `26a8a90`) is in
this repository's history at commit `5a6079c`. 0.11.5.1 changes three operator
screens and nothing else:

- **Gateway settings** are sections by task (approval and pricing, the REST
  API, receipts and callbacks, call records, diagnostics, vendor and listener
  defaults) of compact rows: switches, two- and three-way choices, numbers with
  their unit, lists as chips. Each row says where its value comes from, and
  whether the running gateway has picked up a saved value yet. Diagnostics moves
  from its own tab into Settings, and every edit waits for one Save bar.
- **Error codes** shows every list in a column on the left (the Every vendor
  list, and each vendor marked Inherits or Own list) beside the one being
  edited. A vendor's answer for unmapped codes is a three-way choice: inherit,
  as sent, or as 018. Edits, the passthrough switch included, wait for Save.
- **The bar above each page** no longer repeats the page's title and subtitle.

No migration, no new grant and no new setting. A panel on 0.11.5.0 upgrades
with `fireflo-panel-install update`; the gateway is not touched.

**And re-cut once more the same day, with control panel 0.11.5.2**; the gateway
binary is again the one first published. The 0.11.5.1 tarball (SHA-256
`3ab073eb…a28a754`) is in this repository's history at commit `9fbcecf`.
0.11.5.2 changes two operator screens and nothing else:

- **Filters** are grouped in a column on the left by what they match
  (destination, sender ID, product and login, account, message content), with
  Unused, Off or empty and Duplicates groups. Each filter reads as a sentence
  and is badged with the routing and pricing rules that use it. A new filter is
  made in three guided steps, and the panel says when one would test exactly
  what another already does.
- **Routing** lists the routing tables in a column on the left, beside the one
  open. Rules read as sentences ("When destination starts with +91 → smppsim"),
  the rules default routing wrote fold into one line, and a rule below a
  catch-all is marked as never reached. A rule is edited in a dialog using the
  same guided fields as filters; edits, reorders and on/off switches wait for
  one Save bar. Start here shows how a message travels from `default`, and the
  routing tester and the delivery check share one page.

No migration, no new grant and no new setting. A panel on 0.11.5.0 or 0.11.5.1
upgrades with `fireflo-panel-install update`; the gateway is not touched.

**And re-cut again on 2026-10-13, with control panel 0.11.5.3**; the gateway
binary is still the one first published. The 0.11.5.2 tarball (SHA-256
`a538dbb6…4955640`) is in this repository's history at commit `08467dc`.
0.11.5.3 changes operator screens and nothing else:

- **Vendors and Servers** open with a live traffic chart for the last fifteen
  minutes: MT/s and DLR/s from the call records, and messages queued from the
  gateway's live health, in three colours. It totals every vendor, or every
  account on Servers, and narrows to one; an account is found by typing part of
  its id or name. Queued is drawn from when the page is opened, because the
  gateway does not store queue depth.
- **Queues** is rebuilt as the path a message takes: broker, router, then each
  vendor with what is waiting and what is scheduled to retry, and whether it grew
  since the last read. Choosing a stage lists its messages below.
- **A vendor's page** keeps Messages, Error codes, Edit and Disable in the card's
  footer, with Stop sending and Restart at its right.
- **Pricing export and import** explain a header-only file: an export taken
  while nothing is priced has no rows, and is offered as a template to fill in.

No migration, no new grant and no new setting. The chart reads `cdr_submit`
and `cdr_final` through indexes they already have. A panel on 0.11.5.0 to
0.11.5.2 upgrades with `fireflo-panel-install update`; the gateway is not
touched.

### 0.11.4

**0.11.4 CARRIES A DATABASE MIGRATION, `V1.52.0`.** It is the first since
0.10.0. `fireflo-install update` runs it before it starts the new binary, as it
always has; on a gateway you migrate by hand it is `fireflo db migrate`. What
it does to an existing database:

- **New table `app_user`** — who may sign in, as `admin`, `operator` or
  `customer`, with a PBKDF2-SHA256 password hash. A reseller is not a role: it
  is a customer user on an account that resells.
- **Every account with an email address becomes a customer user** with no
  password, so the sign-in link it already had keeps working. Nothing else
  about the account changes.
- **`app_login_token` gains `user_id`** (required) and its `account_id` becomes
  optional, because operators can now be sent a link too. Unspent tokens for an
  account with no address are deleted; they were never redeemable and live
  fifteen minutes.
- **`app_customer_access_log` gains `user_id`** and accepts the new sign-in
  events; **new table `app_operator_access_log`** records operator sign-ins,
  failures and links. Both are insert-only by grant.

It is additive, so rolling the **gateway** back to 0.11.3 still works against a
migrated schema. **The control panel cannot go back**: a 0.11.3.x panel writes
sign-in links without a `user_id` and every one fails.

**THE PANEL'S DATABASE ROLE NEEDS NEW GRANTS, or nobody can sign in.** Run the
grant block in `panel/README.md` as the database owner, or at least:

```
GRANT SELECT, INSERT, UPDATE ON app_user TO fireflo_rw;
GRANT INSERT, SELECT ON app_operator_access_log TO fireflo_rw;
GRANT USAGE, SELECT ON SEQUENCE app_user_id_seq, app_operator_access_log_id_seq TO fireflo_rw;
```

(with your panel role in place of `fireflo_rw`).

**Upgrade the gateway first, then the panel.** `fireflo-panel-install update`
moves the operator from `OPERATOR_USERNAME` / `OPERATOR_PASSWORD` in
`panel.env` into `app_user` as an admin **with the same password**, and removes
the two keys. If the gateway has not migrated yet it says so and leaves them,
and the old sign-in keeps working until you run it again. A new install creates
the first admin itself and prints the password once.

**Users and passwords live in the gateway's database.** `fireflo user add`,
`passwd`, `list`, `disable` and `enable` manage them from the command line; an
admin manages them in the panel under Security → Users. An account can have
many users. The emailed link stays, as the way back in for anyone who forgets a
password, and operators can now ask for one from the sign-in page. Ten failed
attempts from one address for one user lock that pair out for fifteen minutes.
Every sign-in, failed or not, on either door, is under Reports → Access log.

**Control panel 0.11.4.7** is a reworked interface on the same pages: slate and
the FireFlo green, one type scale and one spacing scale on every page, vendors
and listeners as cards with a page each, routing and pricing organised under
tabs with an **Advanced** switch for the rarely-used fields, a date range on
Messages, and no page that scrolls sideways on a phone.

The licence key compiled into the binary is unchanged, so no install upgrading
to 0.11.4 needs a new licence. The REST panel is still not in this tarball;
the 0.11.3 notes below say where it is.

**This 0.11.4 tarball was re-cut on 2026-10-12 with control panel 0.11.4.6;
the gateway binary in it is byte for byte the one first published.** The first
0.11.4 tarball (SHA-256 `df32b47d…f0e86d7`, panel 0.11.4.5 at `59ccfb3`) had
the reworked operator pages but not yet the customer portal's. 0.11.4.6 brings
the portal to the same type and spacing, and fixes its phone layout: the
navigation and the account card no longer stack above every page, pushing the
page itself below the first screen — the navigation is behind a Menu button and
the balance stays in view as one line. The portal also **no longer shows the
platform's version** on its sign-in page or in its header, which a white-labelled
portal should never have done. A host on the first 0.11.4 tarball upgrades the
panel only, with `fireflo-panel-install update`; the gateway has nothing to do.

**And re-cut once more the same day, with control panel 0.11.4.7**, for one
portal fault. A customer whose account, or whose own user, had been disabled
still got the whole portal frame — navigation, balance, page titles — and only
the panels inside it failed to load. Nothing was exposed: every request for
data was already refused. The portal now answers such a session with a 404, as
its data routes did. The second tarball (SHA-256 `02b6cf50…18fea458`, panel
0.11.4.6 at `27630b9`) has that fault; the gateway binary is unchanged in all
three, and a host on either earlier tarball updates the panel only.

### 0.11.3

**0.11.3 CARRIES NO DATABASE MIGRATION**, and nor did 0.11.2 or 0.11.1, which
were never published here. From 0.11.0 it is a binary swap and the control
panel's own installer; coming from 0.10.0 or 0.9.x, read the 0.11.0 notes below
first.

**This 0.11.3 tarball was re-cut on 2026-10-09 to fix both installers; the
gateway binary in it is byte for byte the one first published.** The first
0.11.3 tarball (SHA-256 `76318825…eec50`, gateway commit `da4a838`, panel commit
`db0fcf9`) had three installer faults. A first `--vhost` install under `/home`
for a service account that did not exist yet was refused as "the application
directory is the account's home", by the gateway and the panel installer alike;
with `--vhost` already given, that refusal suggested a second one, nesting the
install. And the panel's `install` refused a host without Node, the very thing
its package step adds. A host already running the first 0.11.3 tarball has
nothing to update: only the installers changed.

**And re-cut once more the same day**, for one more panel installer fault:
`fireflo-panel-install passwd` used the default account rather than the one the
panel was installed with, so on an install made with `--user` it stopped with
`install: invalid user: 'fireflo'` and changed nothing. The second tarball
(SHA-256 `c159d6d9…0799b`, panel commit `1bf7a03`) has that fault; on a host
installed from it, `passwd --user <the panel's account>` works around it.

**And a third time, with control panel 0.11.3.2**, whose sign-in page says why
a sign-in failed when the password was never the cause. A panel reached over
plain `http://` with an `https://` `AUTH_URL` drops its sign-in cookie, and every
attempt was reported as "Check the credentials" — the real reason, `MissingCSRF`,
was only in the service log. It now says the password was not checked and, on
plain HTTP, names the two `panel.env` lines that fix it for that address. The
third tarball (SHA-256 `50892fe6…df79c`, panel 0.11.3.1 at `4fb90c8`) is
otherwise the same; the gateway binary is unchanged in all four.

**Ship the control panel with it; the REST panel is not in this tarball.**
`panel/` is the control panel 0.11.3.2, matched to this gateway. The REST panel
has not changed since 0.11.0.0, carries no version check against the gateway,
and keeps running beside 0.11.3 as it is. A host that does not have it yet takes
it from the 0.11.0 tarball.

**With RabbitMQ, accepted work now survives a restart.** With
`smsg.queue.provider=rabbitmq`, a `/secure/sendbatch` batch is published whole
to `fireflo.batch.in` and answered only once the broker confirms it; it is split
into one message per recipient on `fireflo.batch` and each is acknowledged after
it is sent and its caller called back. A receipt on its way to a customer sits
on `fireflo.dlr.forward` until it is delivered, given up on, or its retry is
safely queued. Before this, both lived in memory and a restart lost them — a
10,000-message pilot restarted once lost 1,139 receipts. **The gateway declares
these queues itself; its broker user needs configure rights on its vhost, as it
already does for `fireflo.submit`.** A batch the broker cannot take is refused
with 503 rather than accepted into memory. Without a broker nothing changes:
batches and receipts run in memory as before.

**A restart no longer sends anyone a message twice.** Shutdown used to close the
broker connection while each batch consumer still held a message it had sent
but not acknowledged; after the restart the broker handed those out again. The
batch service now stops first, and waits up to 15 seconds for what is in hand
to be sent and acknowledged before the connection closes. Receipts keep going
onto the broker for as long as the SMPP sessions hand them in.

**Batches really do run side by side.** They ran one after another on a single
thread whatever `smsg.restapi.batch.concurrency` said, so a sendbatch customer
was held to one message per callback round trip — about 15 a second against a
real web application. Each now runs on its own thread, up to that setting
(default 4). **A sendbatch caller will see its messages leave faster, and its
callback endpoint called faster**, after this upgrade.

**Bulk callbacks, opt in, per account.** Name an account in
`smsg.callback.bulk.accounts` and its JSON receipts and batch results go as one
POSTed JSON array per address — up to `smsg.callback.bulk.max` items (500), or
`smsg.callback.bulk.linger.ms` after the first (200) — instead of one request
each. Measured on a 10,000-message pilot against a web application: 50 seconds
where one-per-request took about 190, in 91 requests instead of about 20,000.
Each receipt keeps its own retry ladder and callback record. **Turn it on only
for a receiver that accepts a JSON array**; the list ships empty, so nothing
changes until you name an account, and the kannel format is never batched. The
control panel 0.11.3.1 and later shows the three keys under Settings.

**JSON MO forwarding works from the native binary.** Every JSON MO forward from
a native gateway failed with "Failed to serialize MoContext to JSON" and retried
until it gave up; FORM forwards and the JVM build were unaffected.

The licence key compiled into the binary is unchanged, so no install upgrading
to 0.11.3 needs a new licence.

**0.11.0 CARRIES NO DATABASE MIGRATION.** From 0.10.0 it is a binary swap and
each panel's own installer. Coming from 0.9.x you still owe `V1.51.0`, described
under 0.10.0 below, and that is still the first thing to plan for.

**TWO WEBHOOK DEFAULTS CHANGE, and both change what a stock install does.** Read
these before upgrading a gateway that posts receipts anywhere:

- **A receipt target that resolves to a private, loopback or link-local address
  is now refused.** `smsg.webhook.private.targets` ships as `deny`; it was
  `allow`. The case `allow` existed for — posting receipts to an application on
  your own network — is the same case that let any customer's `dlr-url` reach
  whatever the gateway can reach, including this host's own management port or a
  cloud metadata endpoint, on a stock install. **If you post receipts inward, set
  the key to `allow` before you upgrade, or those calls stop.** An estate that
  set it explicitly is untouched. Where you can, name the permitted targets in
  egress firewall rules and leave this at `deny`: resolving a name and then
  connecting to it raises the cost of the attack rather than closing it.
- **`smsg.webhook.retry.interval.ms` keeps its name and its `120000` default and
  changes meaning**, from the wait between every attempt to the wait before the
  first one. Each wait after it doubles, held at an hour, and is drawn with full
  jitter. Ten attempts now span up to 5h 2m — about two and a half on average —
  where the flat reading gave up 18 minutes after the first failure and lost
  every receipt for an endpoint that was down over a lunchtime deploy. A first
  wait set longer than an hour is honoured rather than cut down to the cap.

**A 3xx from a customer's endpoint no longer counts as delivered.** We do not
follow redirects — `smsg.webhook.redirects` defaults to `never` — so a 301 meant
the customer got no payload, no retry, and a delivered receipt in their CDR. The
success window is 2xx on both the DLR and MO paths. **An endpoint that redirects
will now show retries and failures where it used to show successes**, which is
what was happening all along.

**Callbacks to one host are capped at ten in flight**, so a single slow endpoint
no longer absorbs threads and sockets without limit. A receipt waiting out a
retry holds no slot.

**Messages in flight when a vendor's socket dies are no longer lost.** A
`submit_sm` sits in the bind's send window until the vendor answers it; when the
socket died abruptly — peer killed, crashed, network dropped — the window went
with the session and those messages were lost outright: no retry, no CDR row, no
refund, no receipt. At a full window that is everything in flight at that
instant; staging reproduced 22 of 1,199. They are now drained back through the
vendor's normal nack handling, so `maxRetries` and the `status.*` lists decide
what happens to them exactly as they would for an expiry, with the usual unbilled
`cdr_submit` row for the dead attempt. Look for `message.vendor.inflight.reclaimed`
in the log. Two new keys document the quiet-vendor case beside it:
`request.tout` and `window.monitor.interval.millis`, both per vendor instance.

**Delivery receipts are written once, at the provider's answer.** The centrepiece
of this release, and a throughput fix as much as a correctness one. A row was
written at ingress before the provider id was known, then read back to link that
id in — and at rate the vendor's `submit_sm_resp` regularly beat our own write:
a measured 1,532,933 links of 2,777,015 accepted, 55% of the traffic, abandoned,
while the sustained rate sagged from 3,000/s to about 2,350/s on the write
amplification alone. State and correlation are now created together when the
provider id returns, so there is no link step and no race to retry. **If you
alert on `dlr.link.abandoned`, that warning is gone**, along with the link retry
behind it.

**Margin stops being a subtraction across two currencies.** In database mode
`app_rate_rule.currency` is a per-row column, so a customer can be priced in one
currency while the vendor is costed in another. The CDR recorded the customer's
currency on both sides — price arrives first, at ingress — so a USD cost was
stored, rendered and subtracted as though it were AUD. Cost and price now each
carry their own currency, and margin refuses when the two disagree rather than
reporting a number. **Margin over mixed-currency rules was wrong before this and
is worth re-reading.**

**A vendor removed from a weighted group no longer leaves its credit behind.**
Weighted credit is held per member inside the group, and the prune cleared only
the outer map, so a member removed and later added back resumed on the credit it
had left rather than starting level. The timing is what made it bite: a member's
credit is at its most negative immediately after it has won a round, which is
also when an operator is most likely to pull it out. Put back a week later, it
owed that debt before carrying a single message.

**Two hot paths get cheaper.** The sell-side rate merge is memoised, so REST
ingress stops rebuilding it per message — SMPP was never affected, it holds a
binding — and two per-message configuration reads on the SMPP path become cached
fields.

**Both panels are 0.11.0.0, and the control panel carries two fixes past that
stamp.** The session cookie is no longer marked `Secure` on a panel served over
plain http, which is what stopped sign-in working on one; and a sign-in link that
has already been used stops reporting success. **The control panel is worth
upgrading with this gateway if you serve it over http or use emailed sign-in
links.**

**This tarball corresponds to commits, not to a disk.** The packager used to
rsync each panel's working directory in, carrying whatever happened to be
uncommitted on the machine that built it; each panel is now staged with
`git archive HEAD`, and anything uncommitted is named in the build output rather
than shipped. `MANIFEST` records uncommitted changes in the gateway checkout that
built this binary: they were that packaging script itself, still being written.
No gateway or panel source was among them — the only commits between `18d449c`
and this build's own history touch `scripts/make-release` and `docs/`.

**0.10.0 CARRIED A DATABASE MIGRATION, and coming from 0.9.x it is still the
first thing to plan for.**
`V1.51.0` moves the gateway's own credit-reservation bookkeeping out of
`balance_ledger` into a table of its own, **deleting those rows** as it goes, and
adds a trigger that refuses `DELETE` on `balance_ledger` from then on. The point
is that the record of money becomes append-only: nothing in it can be removed,
by anybody, without deliberately disabling that trigger.

Nothing is lost that anybody computes money from — the rows it removes net to
zero and no balance is derived from them — and `balance + reserved` is unchanged
on every account. But migrations are **forward-only**, so the rollback path is a
restore rather than a reverse migration. **Take the backup before, not after.**
`fireflo-install update` runs it.

**0.10.0 MOVED TWO SHIPPED DEFAULTS, and both change behaviour on an estate
that never set them.** Read these before upgrading a busy gateway from 0.9.x:

- **A vendor group now actually fails over.** Its liveness test never fired when
  a vendor lost its connections, so traffic kept queueing on a dead carrier while
  a healthy one sat idle — measured at 2,837 messages piled up against 0 delivered
  to the alternative. If you run more than one vendor in a group, this is the
  release to take.
- **`maxRetries` ships as 3, not 1.** At 1 the first refusal failed the message,
  so nothing retryable was ever retried; a carrier throttling at peak cost a fifth
  of the traffic offered to it. Expect slightly more submit_sm per message and
  materially fewer lost ones. An estate that set the key explicitly is untouched.

**0.10.0 also made the SMPP ingress rate limit bind where it did not.**
`conf.maxRate` was
enforced per *session*, so a customer with four binds got four times their limit.
It is now per account, and a throttled submit is answered with a proper
`submit_sm_resp ESME_RTHROTTLED` rather than a `generic_nack` their client
probably ignored. **If you sell a rate, check what your customers were actually
getting before this** — some may be sending above their plan today.

**0.10.0 gave resellers credit transfers over the API.** `POST /secure/transfers` and two
companions let an account that holds others fund them, or take credit back, with
the gateway credentials it already has. See
[Moving credit to your accounts](https://docs.fireflo.au/developers/billing/credit-transfers).

**0.9.23 is withdrawn on capability** — installs running it are fine, and nothing
in it is dangerous.

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

**THE CONTROL PANEL IS INCLUDED**, at `panel/`, as source with its own
installer inside its own tree. The customer-facing REST panel was included from
0.9.11 to 0.11.0 and is not in 0.11.3, 0.11.4 or 0.11.5 (see above). Neither is required: the
gateway installs and runs without them.

The control panel is paired by version — its first three numbers name the
gateway release it was built against — and the one in this tarball is
**0.12.10.0**, so it matches the gateway beside it. A panel you already have is **not** touched by
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

0.12.10 answers `MCowBQYDK2VwAyEA7cEZKZae5xBb8uwIgvCmxBzW7ceOKl0YiFE1AburdAI=`, and
that is the only key in it — unchanged since 0.8.9, so an install upgrading from
any of those needs no new licence. That is a public value; publishing it is safe and is
what makes a build identifiable. A mismatch here presents as licences being
rejected as MALFORMED, which reads like a fault in the licence server rather
than in the binary — the reason it is worth checking directly.

## What is not here

The private signing key is **not in this repository and must never be**, in any
form, in any commit, including history. See `.gitignore`.

**The REST panel is not in this tarball.** The control panel is, at `panel/`;
the REST panel 0.11.0.0 is in the 0.11.0 tarball, in this repository's history
at `42d506e`. Neither is needed to install or run the gateway, and neither is
touched by upgrading the gateway — each is installed and upgraded by its own
installer, which lives inside its own directory.
