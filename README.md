# FireFlo releases

Built release artefacts for the FireFlo SMS Gateway, kept so that any version
ever handed to a customer can be recovered byte for byte and identified later.

FireFlo is commercial software, licensed per deployment, created and maintained
by [Remotiq](https://fireflo.au). Downloading a build from here grants no
licence to run it — see `LICENSE` inside the tarball. An unlicensed install
starts and carries traffic, but stops adopting configuration changes.

## Current

| | |
|---|---|
| **Version** | 0.9.11 |
| **File** | `fireflo-0.9.11-linux-x86_64.tar.gz` |
| **SHA-256** | `d1314376f6209597e34cca454c3758e1286ebcf9aa5fd13d52e0a6736bbfcc31` |
| **Built** | 2026-09-04, from gateway commit `d5299bc` |
| **Control panel** | 0.9.11.0, included at `panel/` |
| **REST panel** | 0.9.11.0, included at `rest-panel/` |
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

**Only the current release is published here.** Builds before 0.9.11 have been
withdrawn and their tarballs removed from this tree.

**Do not install 0.9.2 if you still have it.** It bundled the control panel
for the first time but placed the panel's installer where it cannot find the
panel source, so installing the panel from that tarball fails with a message
about the checkout not looking like the control panel. 0.9.3 is that fix; the
gateway half of 0.9.2 was sound.

**0.9.11 CARRIES BOTH PANELS**, which no release since 0.9.4 has. The operator's
control panel is at `panel/` and the customer-facing REST panel at `rest-panel/`,
each as source with its own installer inside its own tree. Neither is required:
the gateway installs and runs without them.

They are paired by version — a panel's first three numbers name the gateway
release it was built against — and both in this tarball are **0.9.11.0**, so they
match the gateway beside them. A panel you already have is **not** touched by
upgrading the gateway from here; it is upgraded by its own installer.

**The gateway binary is unchanged since 0.9.8.** 0.9.9, 0.9.10 and 0.9.11 all
carry the same code; what changed is what travels beside it — a corrected README
in the first two, and the panels in this one. There is no gateway behaviour in
any of them to hurry for.

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

0.9.11 answers `MCowBQYDK2VwAyEA7cEZKZae5xBb8uwIgvCmxBzW7ceOKl0YiFE1AburdAI=`, and
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
