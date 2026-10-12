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
| **Version** | 0.11.4 — **carries a database migration**, read [the 0.11.4 notes](#earlier-builds) before upgrading |
| **File** | `fireflo-0.11.4-linux-x86_64.tar.gz` |
| **SHA-256** | `02b6cf50ebe69febc389a12ef9f168751e5c2449b70d2cba002ba14f18fea458` |
| **Built** | 2026-10-12, from gateway commit `533c48e` — re-cut with control panel 0.11.4.6, see [the 0.11.4 notes](#earlier-builds) |
| **Control panel** | 0.11.4.6, included at `panel/`, from commit `27630b9` |
| **REST panel** | not included — unchanged at 0.11.0.0, see [the 0.11.3 notes](#earlier-builds) |
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
scp fireflo-0.11.4-linux-x86_64.tar.gz SHA256SUMS SHA256SUMS.asc SIGNING-KEY.asc setup.sh root@newhost:/root/
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
tar xzf fireflo-0.11.4-linux-x86_64.tar.gz
cd fireflo-0.11.4-linux-x86_64
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
`rest-panel/scripts/`. **0.11.4 does not carry it**: take it from the 0.11.0
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

**Only the current release is published here.** Builds before 0.11.4 have been
withdrawn and their tarballs removed from this tree. 0.11.3's last tarball is in
this repository's history at commit `2af1923`. 0.11.0's is still in this
repository's history, at commit `42d506e`, and is where the REST panel lives
for now.

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

**Control panel 0.11.4.6** is a reworked interface on the same pages: slate and
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
0.9.11 to 0.11.0 and is not in 0.11.3 or 0.11.4 (see above). Neither is required: the
gateway installs and runs without them.

The control panel is paired by version — its first three numbers name the
gateway release it was built against — and the one in this tarball is
**0.11.4.6**, so it matches the gateway beside it. A panel you already have is **not** touched by
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

0.11.4 answers `MCowBQYDK2VwAyEA7cEZKZae5xBb8uwIgvCmxBzW7ceOKl0YiFE1AburdAI=`, and
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
