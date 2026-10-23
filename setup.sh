#!/bin/sh
# Prepare a host for FireFlo.
#
#   sudo ./setup.sh [--role ROLE] [options]
#
# SUPPORTED HOSTS
#
#   apt   Ubuntu 20.04 focal, 22.04 jammy, 24.04 noble, 25.04 plucky;
#         Debian 11 bullseye, 12 bookworm, 13 trixie
#   dnf   RHEL-family 9 or newer: CentOS Stream 9, Rocky Linux 9, AlmaLinux 9,
#         RHEL 9 (and, best effort, Fedora). Recognised from /etc/os-release
#         ID or ID_LIKE. Packages come from BaseOS and AppStream only -- no
#         EPEL, no CRB -- with the postgresql:16 and nodejs:22 module streams
#         enabled where the release has them (EL9 does; EL10 and Fedora have
#         no modules and their default packages are new enough)
#
# Anything else is refused, naming what /etc/os-release said.
#
#   --role ROLE        what this host is for. One of:
#                        all      everything on one box: PostgreSQL, a single
#                                 Redpanda node advertising 127.0.0.1, Node for
#                                 the control panel, the gateway's client tools.
#                                 This is the DEFAULT and what 0.13 did, with
#                                 Redpanda where RabbitMQ used to be (or
#                                 Apache Kafka, with --broker kafka)
#                        gateway  a gateway node. Client tools only: no database
#                                 server, no broker, no Node. Pair with --db-host
#                                 and --kafka-bootstrap at install time
#                        db       the PostgreSQL server the gateway nodes share
#                        broker   a Redpanda node, alone or one of three; or
#                                 with --broker kafka, one Apache Kafka node
#                        panel    the control panel: Node 22 and a PostgreSQL client
#   --allow-from CIDR  db only, repeatable. A gateway subnet that may reach
#                      PostgreSQL. With it, pg_hba.conf and listen_addresses are
#                      edited (each file backed up first) and the server
#                      restarted. Without it nothing is edited: the lines are
#                      printed with placeholders for you to apply
#   --advertise-ip IP  broker only. The address other hosts reach this node on.
#                      Default: the first non-loopback address, printed so you
#                      can check it. --role all always advertises 127.0.0.1
#   --ips A,B,C        broker only. The addresses of all three nodes of a
#                      cluster, this one included. Without it the node starts
#                      a cluster of one. Redpanda only
#   --broker KIND      broker|all only. Which Kafka-protocol broker to install:
#                        redpanda  the DEFAULT. One binary, from Redpanda's
#                                  apt or rpm repository
#                        kafka     Apache Kafka in KRaft mode, ONE node, from
#                                  the apache.org tarball (SHA-512 checked) --
#                                  no package manager, so the same on apt and
#                                  dnf hosts. A JVM with a fixed heap, which is
#                                  the better fit for a small VM. Needs Java 17
#                                  or newer: an existing 'java', or --with-java
#   --kafka-home DIR   --broker kafka: where the tarball is unpacked (/opt/kafka)
#   --kafka-data DIR   --broker kafka: log.dirs is DIR/data (/var/lib/kafka)
#   --kafka-heap SIZE  --broker kafka: the JVM heap, -Xms and -Xmx (1g)
#   --kafka-partition-cap MB
#                      --broker kafka: log.retention.bytes, PER PARTITION (1024).
#                      Retention is also 168 hours; whichever is hit first
#   --with-java        also install Temurin JDK 25, from Adoptium. OFF by
#                      default: the shipped gateway is a native image and opens
#                      no JDK. You want this to BUILD from source, or to run
#                      --broker kafka on a host with no Java 17+
#   --no-node          --role all only: skip Node. Node 22 is installed because
#                      the control panel needs it and Ubuntu ships 18, which
#                      Next.js will not run on
#   --no-postgres      --role all only: skip the PostgreSQL server
#   --kafka-kraft-notes  print a note on Apache Kafka (KRaft) and exit
#   --dry-run          print every command and touch nothing
#   --yes              do not prompt
#   --help
#
#   --no-rabbitmq      refused. RabbitMQ left FireFlo in 0.14; see below
#
# Environment: REDPANDA_VERSION pins the Redpanda package (deb or rpm
# version-release, e.g. 25.2.1-1); KAFKA_VERSION picks the Apache Kafka
# release for --broker kafka (default 4.4.0).
#
# Testing: with --dry-run, and only then, FIREFLO_SETUP_OS=rhel|ubuntu|debian
# pretends this is a bare CentOS Stream 9, Ubuntu noble or Debian bookworm
# host, and FIREFLO_SETUP_OS_RELEASE=<file> reads that file in place of
# /etc/os-release. Either one without --dry-run is refused.
#
# WHAT THIS IS FOR
#
# 'fireflo-install' installs the gateway. It does NOT install the services the
# gateway talks to: its package step adds postgresql-CLIENT and no server, and
# it never installs a broker. So between unpacking the tarball and running the
# installer there is a step nobody wrote down. This is that step.
#
# From 0.14 the services need not share a host with the gateway. The database,
# the broker, the gateway nodes and the control panel can each be their own
# machine, and a gateway can be two or three nodes behind a TCP load balancer.
# --role is how you tell this script which of those machines it is standing on.
# Run it once per host, with that host's role; --role all is still the one-box
# install and still the right answer for most deployments.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * It does not create a database, a role or a password. Installing a package
#     is impersonal and reversible; creating a role and writing its password to
#     a file is neither, and it is not a decision a setup script should make on
#     your behalf. You create them, and pass them to fireflo-install. The
#     summary at the end prints the commands.
#   * It does not create a Redpanda user or ACL, or turn SASL on, for the same
#     reason. A fresh Redpanda node accepts any client that can reach port 9092,
#     which is correct on a single box where 9092 is not opened to anybody, and
#     is why the firewall lines in the summary come BEFORE the ACL lines.
#   * It does not download, verify or install FireFlo, and it never asks for a
#     licence key. Keeping those separate is what lets this file be read in full
#     before it is run -- which you should do, because you are about to run it
#     as root.
#   * It does not create a service user, a systemd unit or any FireFlo
#     configuration (--broker kafka's broker user and unit aside; see below).
#     Those are fireflo-install's, which does them carefully.
#     The one host-level edit it will make is PostgreSQL's listen address and
#     pg_hba.conf, and only when you name the subnet with --allow-from.
#   * It never writes firewall rules. It prints them, per role -- ufw lines on
#     Debian and Ubuntu, firewall-cmd lines on RHEL-family hosts or wherever
#     firewalld is running -- because which hosts may reach which port is a
#     fact about YOUR network, and a firewall on a host you are ssh'd into is
#     not something to change from a script.
#   * It never changes SELinux: not its mode, not its policy, not a file
#     context. Where a data directory has been moved off its default on an
#     Enforcing host, it prints the semanage and restorecon lines instead.
#   * The --broker kafka path is the one exception to "packages only": it
#     creates a 'kafka' system user, /etc/kafka/server.properties and
#     /etc/systemd/system/kafka.service, because a tarball brings none of
#     those. Each is written only when absent, never overwritten.
#
# This file is not signed. Neither are the release tarballs. Read it.

set -eu

ROLE=all
WITH_JAVA=no
WITH_NODE=yes
WITH_POSTGRES=yes
DRY_RUN=no
ASSUME_YES=no
ALLOW_FROM=""          # space-separated CIDRs, from --allow-from
ADVERTISE_IP=""        # from --advertise-ip; auto-detected for --role broker
SEED_IPS=""            # from --ips, comma-separated as rpk wants it
BROKER=redpanda        # from --broker
FORCED_OS=no           # yes when FIREFLO_SETUP_OS / _OS_RELEASE drive a dry run
PKG=""                 # apt or dnf, from detect_host

# The oldest PostgreSQL the schema runs on. Below this the Flyway migrations
# fail partway, which leaves a half-migrated database rather than a clean
# refusal -- so it is checked before a server is installed, not after.
PG_MIN_MAJOR=14

# Node 20 is the floor Next.js needs; 22 is what gets installed when it is
# missing. Both matter: a host that already has 20 is fine and must not be
# given a third-party apt repository it does not need.
NODE_MIN_MAJOR=20
NODE_INSTALL_MAJOR=22

# The PostgreSQL module stream enabled on a dnf host. EL9's DEFAULT
# postgresql, with no stream enabled, is 13 -- below the floor -- so on EL9 the
# stream is not a preference, it is the difference between a server the
# migrations run on and one they fail against partway.
PG_DNF_STREAM=16

# Redpanda. Empty installs whatever the repository's stable channel is today;
# set REDPANDA_VERSION in the environment to pin the package (the full
# version-release string, e.g. 25.2.1-1, for the deb or the rpm alike). Pin it
# when you are building the second and third node of a cluster: the three
# should match, and 'stable' moves.
REDPANDA_VERSION=${REDPANDA_VERSION:-}
REDPANDA_REPO_SETUP='https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh'
REDPANDA_RPM_SETUP='https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.rpm.sh'

# Below these, Redpanda in production mode is the wrong broker for the host.
# Learned on the .101 staging VM: Redpanda sizes itself to the machine -- one
# shard per core, most of the RAM reserved up front -- and on a small VM it
# either refuses to start or starves everything else on the box. Overridable
# so the warning itself can be exercised in a dry run.
BROKER_MIN_MEM_MB=${BROKER_MIN_MEM_MB:-4096}
BROKER_MIN_DISK_GB=${BROKER_MIN_DISK_GB:-20}

# Apache Kafka, for --broker kafka. The tarball is fetched from
# downloads.apache.org, which carries only current releases, falling back to
# archive.apache.org, which carries all of them -- so a pinned KAFKA_VERSION
# keeps working after Apache rotates it off the main site.
KAFKA_VERSION=${KAFKA_VERSION:-4.4.0}
KAFKA_SCALA=2.13
KAFKA_MIRRORS='https://downloads.apache.org/kafka https://archive.apache.org/dist/kafka'
KAFKA_HOME=/opt/kafka
KAFKA_DATA=/var/lib/kafka
KAFKA_HEAP=1g
KAFKA_PARTITION_CAP_MB=1024
KAFKA_CONF_DIR=/etc/kafka
KAFKA_LOG_DIR=/var/log/kafka
KAFKA_JAVA_MIN=17

# Connections the database should allow for: each gateway node opens a pool of
# up to this many, and the remainder covers the panel, the sweeps, psql and
# pg_dump. 16 * N + 30 is what the summary prints.
PG_CONN_PER_GATEWAY=16
PG_CONN_OVERHEAD=30

usage() {
    sed -n '2,/^set -eu/p' "$0" | sed 's/^# \{0,1\}//; $d'
    exit "${1:-0}"
}

say()  { echo "$@"; }
step() { echo; echo "== $1"; }
die()  { echo "setup.sh: $1" >&2; exit 1; }

# Every command that changes the host goes through this, so --dry-run is total
# rather than sprinkled. It is also how this script is tested: there is no
# container in CI, so the dry run IS the test.
run() {
    if [ "$DRY_RUN" = yes ]; then
        echo "   would run: $*"
        return 0
    fi
    "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

# "Is this already on the host", for the checks that decide whether to install
# something. Under a forced OS (a dry run pretending to be another host) the
# answer is always no: the tools found would be THIS machine's, and a dry run
# of a bare CentOS host that skipped Node because the laptop has Node would
# test nothing.
have_host() { [ "$FORCED_OS" = yes ] && return 1; have "$1"; }

pkg_installed() {
    [ "$FORCED_OS" = yes ] && return 1
    case $PKG in
        dnf) rpm -q "$1" >/dev/null 2>&1 ;;
        *)   dpkg -s "$1" >/dev/null 2>&1 ;;
    esac
}

# Enabling a service is not the same as installing one, and only the second is
# always possible. In a container -- a Docker build, a chroot, an LXC without
# systemd -- there is no PID 1 to talk to, and 'systemctl enable' fails with
# "Failed to connect to bus: Host is down".
#
# Under 'set -e' that aborted the whole run at the FIRST service, so PostgreSQL
# installed, and the broker and Node then did not, and the operator was left
# with a half-prepared host and a message about a bus. Found by running this in
# a container rather than by reasoning about it.
#
# The package is what this script is really for; enabling it is a convenience
# that only means anything where something can act on it. So a missing systemd
# is reported and stepped over, not treated as a failure.
have_systemd() { have systemctl && [ -d /run/systemd/system ]; }

service_enable() {
    if [ "$DRY_RUN" = yes ]; then
        echo "   would run: systemctl enable --now $1"
        return 0
    fi
    if ! have_systemd; then
        echo "   systemd is not running here, so $1 was installed but not enabled."
        echo "   Start it yourself, or enable it when this image is booted."
        return 0
    fi
    systemctl enable --now "$1"
}

confirm() {
    [ "$ASSUME_YES" = yes ] && return 0
    [ -t 0 ] || return 0          # a pipe is not a person; --yes is implied
    printf '%s [Y/n] ' "$1"
    read -r _a || return 1
    case ${_a:-y} in [Nn]*) return 1 ;; *) return 0 ;; esac
}

# A timestamped copy next to the original, so 'diff' shows what this script
# changed and 'cp' puts it back. Never overwrites an earlier backup.
backup() {
    _bak="$1.bak.$(date +%Y%m%d-%H%M%S)"
    if [ "$DRY_RUN" = yes ]; then
        say "   would back up $1 -> $_bak"
        return 0
    fi
    cp -a "$1" "$_bak"
    say "   backed up $1 -> $_bak"
}

# Standard input to file $1 with mode $2. A dry run prints the content instead,
# so a file this script would create can be read before it exists.
write_file() {
    if [ "$DRY_RUN" = yes ]; then
        say "   would write $1 (mode $2):"
        sed 's/^/   | /'
        return 0
    fi
    cat > "$1"
    chmod "$2" "$1"
    say "   wrote $1"
}

# ---------------------------------------------------------------------------
# the host
# ---------------------------------------------------------------------------
# On apt hosts, Adoptium, NodeSource and Redpanda all publish per CODENAME, not
# per version number. A release none of them publishes for has no correct action available,
# and writing the sources.list entry anyway would 404 at the next 'apt update'
# -- breaking package management on the host for everything else, discovered
# weeks later by somebody who never ran this script. So an unknown codename
# refuses.
#
# The family comes from /etc/os-release: ID first, then each ID_LIKE word, so
# Rocky ("rhel centos fedora") and Alma ("rhel centos fedora") land on dnf with
# CentOS and RHEL. Debian and Ubuntu are matched on ID alone, as before: a
# derivative (Mint, Pop!_OS) has its own codenames, which the per-codename
# repositories below do not publish for, so it is refused with what was found.
detect_host() {
    _osr=/etc/os-release
    ID=""; ID_LIKE=""; VERSION_ID=""; VERSION_CODENAME=""; PRETTY_NAME=""
    if [ -n "${FIREFLO_SETUP_OS:-}${FIREFLO_SETUP_OS_RELEASE:-}" ]; then
        [ "$DRY_RUN" = yes ] || die "FIREFLO_SETUP_OS and FIREFLO_SETUP_OS_RELEASE are test hooks for --dry-run
            and nothing else. Unset them to set up this host for real."
        FORCED_OS=yes
    fi
    case ${FIREFLO_SETUP_OS:-} in
        "")
            if [ -n "${FIREFLO_SETUP_OS_RELEASE:-}" ]; then _osr=$FIREFLO_SETUP_OS_RELEASE; fi
            case $_osr in */*) ;; *) _osr=./$_osr ;; esac     # '.' searches PATH without a slash
            [ -r "$_osr" ] || die "no $_osr -- cannot tell what this host is."
            # shellcheck disable=SC1090
            . "$_osr" ;;
        rhel|centos)
            ID=centos; ID_LIKE="rhel fedora"; VERSION_ID=9
            PRETTY_NAME="CentOS Stream 9 (simulated by FIREFLO_SETUP_OS)" ;;
        ubuntu)
            ID=ubuntu; ID_LIKE=debian; VERSION_ID=24.04; VERSION_CODENAME=noble
            PRETTY_NAME="Ubuntu 24.04 LTS (simulated by FIREFLO_SETUP_OS)" ;;
        debian)
            ID=debian; VERSION_ID=12; VERSION_CODENAME=bookworm
            PRETTY_NAME="Debian GNU/Linux 12 (simulated by FIREFLO_SETUP_OS)" ;;
        *) die "FIREFLO_SETUP_OS='$FIREFLO_SETUP_OS' is not rhel, ubuntu or debian
            (or use FIREFLO_SETUP_OS_RELEASE=<an os-release file>)." ;;
    esac
    OS_ID=${ID:-unknown}
    OS_LIKE=${ID_LIKE:-}
    OS_VER=${VERSION_ID:-unknown}
    OS_MAJOR=$(major_of "$OS_VER")
    OS_NAME=${VERSION_CODENAME:-}
    OS_PRETTY=${PRETTY_NAME:-$OS_ID $OS_VER}

    case $OS_ID in
        ubuntu|debian) PKG=apt ;;
        *) for _like in $OS_ID $OS_LIKE; do
               case $_like in rhel|centos|rocky|almalinux|fedora) PKG=dnf; break ;; esac
           done ;;
    esac
    case $PKG in
        apt) detect_apt_host ;;
        dnf) detect_dnf_host ;;
        *) die "$OS_PRETTY is not supported (ID=$OS_ID, ID_LIKE=${OS_LIKE:-none}, VERSION_ID=$OS_VER).
            This script handles Ubuntu and Debian (apt), and RHEL-family 9 or newer -- CentOS
            Stream, Rocky, AlmaLinux, RHEL -- (dnf). See the header and do the steps by hand." ;;
    esac

    # Which firewall the printed rules are for. Only printed, never applied.
    # firewalld wherever it is running; on a dnf host also when it is not,
    # because that is the firewall the family ships and the one you would turn on.
    FW=ufw; FW_ACTIVE=no
    if [ "$FORCED_OS" != yes ] && have systemctl && systemctl is-active --quiet firewalld 2>/dev/null; then
        FW=firewalld; FW_ACTIVE=yes
    elif [ "$PKG" = dnf ]; then
        FW=firewalld
    fi
}

detect_dnf_host() {
    OS_ARCH=$(uname -m)
    [ -n "$OS_MAJOR" ] && [ "$OS_MAJOR" -ge 9 ] 2>/dev/null || die "$OS_PRETTY (VERSION_ID=$OS_VER) is older than this script handles on dnf: 9 or newer.
            EL8's module streams, Adoptium paths and Python differ enough that guessing would
            leave you a half-prepared host. Install postgresql-server (14+), redpanda and nodejs
            (20+) by hand as the role needs, then run './scripts/fireflo-install check'."
    case $OS_ID in
        # Fedora-like, but its releasever (2023) addresses no Adoptium or
        # Redpanda path written for EL, and it has no module streams.
        amzn) die "$OS_PRETTY is Fedora-derived but not RHEL-compatible enough for this script
            (its \$releasever addresses no Adoptium or Redpanda repository written for EL).
            Install the packages by hand, then run './scripts/fireflo-install check'." ;;
        fedora) OS_NAME="fc$OS_MAJOR"; ADOPTIUM_DISTRO=fedora ;;
        *)      OS_NAME="el$OS_MAJOR"; ADOPTIUM_DISTRO=centos ;;
    esac
    [ "$FORCED_OS" = yes ] || have dnf || die "no dnf on $OS_PRETTY. This script handles dnf-based RHEL-family hosts."
}

detect_apt_host() {
    OS_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    [ -n "$OS_NAME" ] || die "/etc/os-release has no VERSION_CODENAME, and the Adoptium, NodeSource
            and Redpanda repositories are addressed by codename. Cannot continue safely."

    # The allow-list is the whole point of the paragraph above. Without it an
    # unrecognised codename does not fail -- it succeeds, writing a
    # sources.list.d entry for a suite that does not exist, which breaks
    # 'apt update' for everything else on the host and is found much later by
    # somebody who never ran this. Refusing is the only honest outcome, and it
    # costs the operator one apt install they can do by hand.
    case "$OS_ID $OS_NAME" in
        "ubuntu focal"|"ubuntu jammy"|"ubuntu noble"|"ubuntu plucky") ;;
        "debian bullseye"|"debian bookworm"|"debian trixie") ;;
        *) die "$OS_PRETTY ($OS_NAME) is newer or older than this script knows.
            It will not guess: NodeSource, Adoptium and Redpanda publish per codename, and an apt
            source written for a suite they do not publish breaks package management on this host
            for everything, not just FireFlo.
            Known: ubuntu focal jammy noble plucky; debian bullseye bookworm trixie.
            Install postgresql (14+), redpanda and nodejs (20+) by hand as the role needs, then run
            './scripts/fireflo-install check'." ;;
    esac
    [ "$FORCED_OS" = yes ] || have apt-get || die "no apt-get on $OS_PRETTY. Cannot continue."
}

# The PostgreSQL major this release's own repository would install. Checked
# BEFORE installing, because a server below the floor is worse than none: the
# migrations get partway and stop.
distro_pg_major() {
    case "$OS_ID $OS_NAME" in
        "ubuntu jammy")   echo 14 ;;
        "ubuntu noble")   echo 16 ;;
        "ubuntu plucky")  echo 17 ;;
        "debian bullseye") echo 13 ;;
        "debian bookworm") echo 15 ;;
        "debian trixie")  echo 17 ;;
        *) echo "" ;;
    esac
}

# The SERVER, and only the server. Three ways to get this wrong, all of which
# end the same way -- the script decides a server is present, installs none, and
# fireflo-install fails later on a refused connection, which reads as a
# networking fault rather than a missing package:
#
#   psql        is postgresql-client, which fireflo-install ITSELF installs.
#   pg_config   is libpq-dev (verified with dpkg -S: it is diverted by
#               postgresql-common but owned by libpq-dev), a client dev package.
#   /etc/postgresql/<n>  survives 'apt remove' -- only 'purge' takes it.
#
# The server binary does not survive removal and is shipped by nothing else, so
# that is what gets asked. Highest major wins on a host running two clusters.
#
# On a dnf host the same rule picks different paths: the distribution's
# postgresql-server puts the binary at /usr/bin/postgres (and its version has
# to be asked, the path carries none); PGDG's postgresqlNN-server at
# /usr/pgsql-NN/bin/postgres.
installed_pg_major() {
    [ "$FORCED_OS" = yes ] && return 0
    if [ "$PKG" = dnf ]; then
        {
            if [ -x /usr/bin/postgres ]; then
                /usr/bin/postgres --version 2>/dev/null | sed -n 's/.*) *\([0-9][0-9]*\).*/\1/p'
            fi
            for _pgbin in /usr/pgsql-*/bin/postgres; do
                [ -x "$_pgbin" ] || continue
                echo "$_pgbin" | sed 's#/usr/pgsql-\([0-9]*\)/.*#\1#'
            done
        } | sort -rn | head -1
        return 0
    fi
    for _pgbin in /usr/lib/postgresql/*/bin/postgres; do
        [ -x "$_pgbin" ] || continue
        echo "$_pgbin" | sed 's#/usr/lib/postgresql/\([0-9]*\)/.*#\1#'
    done | sort -rn | head -1
}

# The unit and data directory that go with the server found. PGDG on a dnf
# host names both by major (postgresql-16, /var/lib/pgsql/16/data); the
# distribution packages, on either family, do not.
pg_service() {
    if [ "$PKG" = dnf ] && [ ! -x /usr/bin/postgres ] && [ -n "${PG_MAJOR:-}" ] && [ -x "/usr/pgsql-$PG_MAJOR/bin/postgres" ]; then
        echo "postgresql-$PG_MAJOR"
    else
        echo postgresql
    fi
}

pg_default_datadir() {
    case $(pg_service) in
        postgresql-*) echo "/var/lib/pgsql/$PG_MAJOR/data" ;;
        *)            echo /var/lib/pgsql/data ;;
    esac
}

pg_as_postgres() {
    if have sudo; then sudo -n -u postgres "$@"
    elif have runuser; then runuser -u postgres -- "$@"
    else return 1
    fi
}

# postgresql.conf and pg_hba.conf, into PG_CONF and PG_HBA (and the data
# directory into PG_DATA_DIR, for the SELinux note). On apt hosts they are
# where the Debian packaging puts them, as before. On a dnf host they live in
# the data directory, which can be anywhere -- so a running server is ASKED
# (SHOW config_file, hba_file), and only a server that is not running yet
# gets the package default.
pg_conf_paths() {
    PG_DATA_DIR=""
    if [ "$PKG" = apt ]; then
        PG_CONF="/etc/postgresql/${PG_MAJOR:-<n>}/main/postgresql.conf"
        PG_HBA="/etc/postgresql/${PG_MAJOR:-<n>}/main/pg_hba.conf"
        return 0
    fi
    PG_CONF=""; PG_HBA=""
    if [ "$FORCED_OS" != yes ] && have psql; then
        PG_CONF=$(pg_as_postgres psql -XAtc 'SHOW config_file' 2>/dev/null || true)
        PG_HBA=$(pg_as_postgres psql -XAtc 'SHOW hba_file' 2>/dev/null || true)
        PG_DATA_DIR=$(pg_as_postgres psql -XAtc 'SHOW data_directory' 2>/dev/null || true)
    fi
    _def=$(pg_default_datadir)
    PG_CONF=${PG_CONF:-$_def/postgresql.conf}
    PG_HBA=${PG_HBA:-$_def/pg_hba.conf}
}

major_of() { echo "$1" | sed 's/^v//; s/[^0-9]*\([0-9]*\).*/\1/'; }

# ---------------------------------------------------------------------------
# dnf helpers
# ---------------------------------------------------------------------------
# Module streams: EL9 ships postgresql and nodejs as several streams, and the
# DEFAULT one is old (postgresql 13, nodejs 16/18). Enabling a stream is a
# persistent choice on the host, so it is made only where nothing has been
# chosen yet: an already-enabled stream is used as it is and never switched
# under installed packages -- dnf refuses that anyway, and the refusal reads
# like a broken repository.
#
# Sets MOD_STREAM to the stream that will be in force (empty where the release
# has no streams for the module, i.e. EL10 and Fedora, whose plain package is
# what installs), and MOD_PRESET=yes when that stream was enabled before us.
dnf_module_stream() {
    _m=$1; _s=$2; MOD_STREAM=""; MOD_PRESET=no
    if ! have dnf; then
        # Only reachable in a forced dry run on a host with no dnf.
        say "   would run: dnf -y -q module enable $_m:$_s   (where the release has that stream; EL9 does)"
        MOD_STREAM=$_s
        return 0
    fi
    _streams=$(dnf -q module list "$_m" 2>/dev/null | awk -v m="$_m" '$1 == m { print $2 }' | sort -u)
    if [ -z "$_streams" ]; then
        say "   $OS_PRETTY has no $_m module streams; its default $_m package is what installs."
        return 0
    fi
    _on=$(dnf -q module list --enabled "$_m" 2>/dev/null | awk -v m="$_m" '$1 == m { print $2; exit }')
    if [ -n "$_on" ]; then
        if [ "$_on" = "$_s" ]; then
            say "   Module $_m:$_s is already enabled."
        else
            say "   Module $_m:$_on is enabled on this host. Not switching streams; using $_on."
        fi
        MOD_STREAM=$_on; MOD_PRESET=yes
        return 0
    fi
    if echo "$_streams" | grep -qx "$_s"; then
        run dnf -y -q module enable "$_m:$_s" || die "dnf module enable $_m:$_s failed; see dnf's message above."
        MOD_STREAM=$_s
        return 0
    fi
    say "   $OS_PRETTY has no $_m:$_s stream (it has: $(echo $_streams)); trying the default package."
    return 0
}

# The major version 'dnf install $1' would give, or nothing if dnf cannot say
# (no dnf in a forced dry run; no metadata as a non-root dry run).
dnf_candidate_major() {
    have dnf || return 0
    _v=$(dnf -q repoquery --latest-limit=1 --qf '%{version}\n' "$1" 2>/dev/null | head -1)
    if [ -n "$_v" ]; then major_of "$_v"; fi
    return 0
}

# The client the gateway and panel hosts get: from the same postgresql:16
# stream as the server, not EL9's default 13. psql 13 talks to a 16 server
# well enough, but pg_dump refuses to dump a server newer than itself, and
# pg_dump is what you reach for at 3am.
dnf_pg_client() {
    if have_host psql; then
        _have=$(major_of "$(psql --version 2>/dev/null | sed 's/^[^0-9]*//')")
        if [ -n "$_have" ] && [ "$_have" -ge "$PG_MIN_MAJOR" ] 2>/dev/null; then
            say "   psql $_have is already installed. Leaving it alone."
            PGC_NOTE="present, $_have"
            return 0
        fi
    fi
    dnf_module_stream postgresql "$PG_DNF_STREAM"
    run dnf -y -q install postgresql
    PGC_NOTE="${MOD_STREAM:+$MOD_STREAM}"
}

# SELinux is read, never changed. The packages label their default data
# directories correctly; a directory moved elsewhere is unlabelled, and an
# Enforcing host then refuses the service in a way that reads as a permission
# bug. So when one has moved, the fix is printed for the operator to run.
selinux_mode() {
    [ "$FORCED_OS" = yes ] && return 0
    if have getenforce; then getenforce 2>/dev/null || true; fi
}

selinux_notes() {
    _mode=$(selinux_mode)
    [ "$_mode" = Enforcing ] || return 0
    _printed=no
    if [ -n "${PG_RESULT:-}" ]; then
        if [ -z "${PG_DATA_DIR:-}" ]; then pg_conf_paths; fi
        _pgdef=$(pg_default_datadir)
        if [ -n "${PG_DATA_DIR:-}" ] && [ "$PG_DATA_DIR" != "$_pgdef" ]; then
            [ "$_printed" = yes ] || { echo; echo "SELinux is Enforcing, and a data directory is off its default. Label it:"; _printed=yes; }
            echo
            echo "  # PostgreSQL data directory $PG_DATA_DIR (default $_pgdef)"
            echo "  sudo semanage fcontext -a -t postgresql_db_t '$PG_DATA_DIR(/.*)?'"
            echo "  sudo restorecon -Rv $PG_DATA_DIR"
        fi
    fi
    if [ "$BROKER" = redpanda ] && [ -n "${BROKER_RESULT:-}" ] && [ -r /etc/redpanda/redpanda.yaml ]; then
        _rpd=$(sed -n 's/^[[:space:]]*data_directory:[[:space:]]*//p' /etc/redpanda/redpanda.yaml | head -1 | tr -d "\"'")
        if [ -n "$_rpd" ] && [ "$_rpd" != /var/lib/redpanda/data ]; then
            [ "$_printed" = yes ] || { echo; echo "SELinux is Enforcing, and a data directory is off its default. Label it:"; _printed=yes; }
            echo
            echo "  # Redpanda data directory $_rpd (default /var/lib/redpanda/data)"
            echo "  sudo semanage fcontext -a -e /var/lib/redpanda/data $_rpd"
            echo "  sudo restorecon -Rv $_rpd"
        fi
    fi
    return 0
}

# The address this host is reached on from the rest of the deployment: the
# source address the kernel would use towards the internet, which on a
# single-NIC server is the right one and on a multi-homed one is a guess that
# the summary prints so you can correct it with --advertise-ip. 'hostname -I'
# is the fallback for a host with no default route at all.
detect_ip() {
    _ip=""
    if have ip; then
        _ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
    fi
    [ -n "$_ip" ] || _ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "$_ip"
}

# Loose on purpose: it catches a bare IP where a CIDR was meant and a typo'd
# option, not every invalid prefix. PostgreSQL rejects the rest at reload and
# says which line.
looks_like_cidr() {
    echo "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$'
}

looks_like_ip() {
    echo "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
}

# ---------------------------------------------------------------------------
# steps
# ---------------------------------------------------------------------------
do_base() {
    step "Base packages"
    if [ "$PKG" = dnf ]; then
        # Every one of these is in BaseOS or AppStream on EL9 -- jq and
        # nmap-ncat (nc) included -- so neither CRB nor EPEL is enabled. A
        # third-party repository this script does not need is one more thing
        # for every later 'dnf update' to trip on.
        #
        # curl only when there is none: EL9 ships curl-minimal, which provides
        # /usr/bin/curl and CONFLICTS with the full curl package, so asking for
        # 'curl' on a stock host is not a no-op but a failed transaction.
        _pk="ca-certificates tar gzip jq rsync python3 nmap-ncat"
        have_host curl || _pk="curl $_pk"
        # shellcheck disable=SC2086
        run dnf -y -q install $_pk
        say "   $_pk"
        return 0
    fi
    run apt-get update -qq
    run apt-get install -y -qq \
        ca-certificates curl wget gnupg apt-transport-https openssl rsync python3
    say "   ca-certificates curl wget gnupg apt-transport-https openssl rsync python3"
}

# What fireflo-install and its smoke test lean on, and what you reach for at
# 3am on a gateway node: psql to look at the shared database, nc to prove a
# port is open before blaming the gateway, jq for the health endpoint.
# fireflo-install adds postgresql-client itself; it is here so a --role gateway
# host is complete before the tarball is even unpacked.
do_gateway_tools() {
    step "Gateway client tools"
    if [ "$PKG" = dnf ]; then
        dnf_pg_client
        run dnf -y -q install nmap-ncat jq rsync python3
        TOOLS_RESULT="postgresql${PGC_NOTE:+ ($PGC_NOTE)} nmap-ncat curl jq rsync python3"
        say "   $TOOLS_RESULT"
        return 0
    fi
    run apt-get install -y -qq postgresql-client netcat-openbsd curl jq rsync python3
    TOOLS_RESULT="postgresql-client netcat-openbsd curl jq rsync python3"
    say "   $TOOLS_RESULT"
}

do_postgres() {
    step "PostgreSQL"
    if [ "$PKG" = dnf ]; then do_postgres_dnf; return 0; fi
    _have=$(installed_pg_major)
    if [ -n "$_have" ]; then
        if [ "$_have" -ge "$PG_MIN_MAJOR" ] 2>/dev/null; then
            say "   PostgreSQL $_have is already installed. Leaving it alone."
            PG_RESULT="present, $_have"
            PG_MAJOR=$_have
            return 0
        fi
        die "PostgreSQL $_have is installed and FireFlo needs $PG_MIN_MAJOR or newer.
            Upgrading a server with data on it is not something this script will do to you.
            Add the PGDG repository and upgrade deliberately: https://www.postgresql.org/download/"
    fi

    _distro=$(distro_pg_major)
    if [ -z "$_distro" ]; then
        say "   Cannot tell which PostgreSQL $OS_PRETTY ships; installing the distribution"
        say "   package and checking afterwards."
    elif [ "$_distro" -lt "$PG_MIN_MAJOR" ] 2>/dev/null; then
        die "$OS_PRETTY ships PostgreSQL $_distro, and FireFlo needs $PG_MIN_MAJOR or newer.
            Installing it would give you a server the migrations fail against partway through.
            Add the PGDG repository first -- https://www.postgresql.org/download/linux/debian/ --
            then re-run this with --no-postgres, or install postgresql-$PG_MIN_MAJOR by hand."
    fi

    run apt-get install -y -qq postgresql postgresql-client
    service_enable postgresql
    PG_RESULT="installed${_distro:+, $_distro}"
    PG_MAJOR=${_distro:-$(installed_pg_major)}
    say "   Installed and enabled. No database, role or password was created -- see the summary."
}

# The RPM, unlike the deb, ships an EMPTY data directory and starts nothing:
# initdb is a step of its own. Run only on an empty directory -- and refused,
# with the reason, on one that holds files but no PG_VERSION, which is
# somebody's half-finished restore rather than something to initialise over.
pg_rhel_initdb() {
    _pgdata=/var/lib/pgsql/data
    if [ "$FORCED_OS" != yes ] && [ -f "$_pgdata/PG_VERSION" ]; then
        say "   $_pgdata is already initialised ($(cat "$_pgdata/PG_VERSION")). Not running initdb."
        return 0
    fi
    if [ "$FORCED_OS" != yes ] && [ -n "$(ls -A "$_pgdata" 2>/dev/null)" ]; then
        die "$_pgdata has files in it and no PG_VERSION -- not an initialised cluster and not
            an empty directory. Not running initdb over it. Look at what is there first."
    fi
    run postgresql-setup --initdb
}

# dnf: the postgresql:16 module stream (see PG_DNF_STREAM), then the server
# and contrib, then initdb, then the unit. The version is checked BEFORE the
# install, as on apt: with no stream enabled EL9 would install 13.
do_postgres_dnf() {
    _have=$(installed_pg_major)
    if [ -n "$_have" ]; then
        if [ "$_have" -ge "$PG_MIN_MAJOR" ] 2>/dev/null; then
            PG_MAJOR=$_have
            say "   PostgreSQL $_have is already installed. Leaving it alone."
            # The one thing done to a present server: a distribution package
            # installed by hand and never initialised cannot start at all.
            if [ "$(pg_service)" = postgresql ]; then
                pg_rhel_initdb
                service_enable postgresql
            fi
            PG_RESULT="present, $_have"
            return 0
        fi
        die "PostgreSQL $_have is installed and FireFlo needs $PG_MIN_MAJOR or newer.
            Upgrading a server with data on it is not something this script will do to you.
            Upgrade deliberately (pg_upgrade, or dump and restore): https://www.postgresql.org/download/linux/redhat/"
    fi

    dnf_module_stream postgresql "$PG_DNF_STREAM"
    _cand=${MOD_STREAM:-$(dnf_candidate_major postgresql-server)}
    if [ -z "$_cand" ]; then
        say "   Cannot tell which PostgreSQL $OS_PRETTY would install; installing and checking afterwards."
    elif [ "$_cand" -lt "$PG_MIN_MAJOR" ] 2>/dev/null; then
        _why=""
        if [ "$MOD_PRESET" = yes ]; then _why=" (module stream postgresql:$_cand is enabled)"; fi
        die "$OS_PRETTY would install PostgreSQL $_cand$_why,
            and FireFlo needs $PG_MIN_MAJOR or newer. Installing it would give you a server the migrations
            fail against partway through. Enable a newer stream -- 'dnf module reset postgresql' then
            'dnf module enable postgresql:$PG_DNF_STREAM' -- or add PGDG, then re-run this."
    fi

    run dnf -y -q install postgresql-server postgresql-contrib
    if [ "$DRY_RUN" != yes ]; then
        _got=$(installed_pg_major)
        if [ -n "$_got" ] && [ "$_got" -lt "$PG_MIN_MAJOR" ] 2>/dev/null; then
            die "dnf installed PostgreSQL $_got, below the $PG_MIN_MAJOR this needs. It has not been
            initialised or started. 'dnf remove postgresql-server' and enable a newer stream."
        fi
        _cand=${_got:-$_cand}
    fi
    pg_rhel_initdb
    service_enable postgresql
    PG_RESULT="installed${_cand:+, $_cand}"
    PG_MAJOR=$_cand
    say "   Installed, initialised and enabled. No database, role or password was created -- see the summary."
}

# Opening the server to the gateway subnet. The distribution package listens on
# loopback only and pg_hba.conf allows only local sockets, which is exactly
# right for --role all and exactly wrong for --role db, where every client is
# another machine.
#
# Edited only when --allow-from names the subnet. Without it the two files are
# left alone and the summary prints the lines with a placeholder, because
# "which subnet are the gateways on" is not something to guess from the
# database host's own address. Each edited file is backed up first, and an
# hba line already present is not added twice, so re-running with the same
# --allow-from is a no-op.
do_postgres_access() {
    [ -n "$ALLOW_FROM" ] || return 0
    step "PostgreSQL access for the gateway subnet"
    pg_conf_paths
    _conf=$PG_CONF
    _hba=$PG_HBA
    if [ "$DRY_RUN" != yes ] && { [ ! -f "$_conf" ] || [ ! -f "$_hba" ]; }; then
        die "expected $_conf and $_hba and found no such files.
            The server was installed somewhere this script does not know; apply the lines the
            summary prints by hand."
    fi

    # listen_addresses: the stock file carries it commented out. Replace a
    # live or commented line in place; append if neither exists. '*' rather
    # than the host's address, because the firewall is what limits who may
    # connect and a server bound to one address stops listening when that
    # address changes.
    if [ "$DRY_RUN" = yes ] || ! grep -Eq "^[[:space:]]*listen_addresses[[:space:]]*=[[:space:]]*'\*'" "$_conf"; then
        backup "$_conf"
        if [ "$DRY_RUN" = yes ]; then
            say "   would set listen_addresses = '*' in $_conf"
        else
            if grep -Eq "^[[:space:]]*#?[[:space:]]*listen_addresses[[:space:]]*=" "$_conf"; then
                sed -i -E "s|^[[:space:]]*#?[[:space:]]*listen_addresses[[:space:]]*=.*|listen_addresses = '*'\t\t# set by FireFlo setup.sh|" "$_conf"
            else
                printf "listen_addresses = '*'\t\t# set by FireFlo setup.sh\n" >> "$_conf"
            fi
            say "   listen_addresses = '*' in $_conf"
        fi
        PG_RESTART=yes
    else
        say "   listen_addresses is already '*' in $_conf."
    fi

    # pg_hba: one line per subnet, scram (the default password encryption from
    # PostgreSQL 14, which is the floor here). 'all all' because the database
    # and role do not exist yet -- this script does not create them -- and
    # scram still demands the password. Narrow it to the role and database
    # once they exist, if you want to.
    _hba_backed=no
    for _cidr in $ALLOW_FROM; do
        _line="host    all             all             $_cidr    scram-sha-256"
        if [ "$DRY_RUN" != yes ] && grep -Eq "^host[[:space:]]+all[[:space:]]+all[[:space:]]+$(echo "$_cidr" | sed 's|[./]|\\&|g')[[:space:]]" "$_hba"; then
            say "   $_hba already allows $_cidr."
            continue
        fi
        if [ "$_hba_backed" = no ]; then backup "$_hba"; _hba_backed=yes; fi
        if [ "$DRY_RUN" = yes ]; then
            say "   would append to $_hba: $_line"
        else
            printf '# FireFlo gateway subnet, added by setup.sh\n%s\n' "$_line" >> "$_hba"
            say "   appended to $_hba: $_line"
        fi
        PG_RESTART=yes
    done

    # listen_addresses needs a restart, not a reload. A restart on a database
    # host that has not been handed to FireFlo yet costs nothing; on a re-run
    # against a live server with nothing to change, it is skipped.
    if [ "${PG_RESTART:-no}" = yes ]; then
        _pgsvc=$(pg_service)
        if [ "$DRY_RUN" = yes ]; then
            say "   would run: systemctl restart $_pgsvc"
        elif have_systemd; then
            systemctl restart "$_pgsvc"
            say "   PostgreSQL restarted."
        else
            say "   systemd is not running here; restart PostgreSQL yourself for the change to take."
        fi
    fi
    PG_ACCESS_RESULT="listen_addresses='*', pg_hba allows: $ALLOW_FROM"
}

# The address the broker advertises, shared by both brokers. --role all is a
# single box and always 127.0.0.1; --role broker takes --advertise-ip or works
# it out, and says which, because a wrong guess here is a gateway that
# connects to the bootstrap address and then cannot reach the broker it is
# told about.
broker_address() {
    if [ "$ROLE" = all ]; then
        ADVERTISE_IP=127.0.0.1
    elif [ -z "$ADVERTISE_IP" ]; then
        ADVERTISE_IP=$(detect_ip)
        [ -n "$ADVERTISE_IP" ] || die "could not work out this host's address; pass --advertise-ip."
        say "   Advertising $ADVERTISE_IP (auto-detected; override with --advertise-ip)."
    fi
}

# Run before the "Proceed?" prompt, so a host too small for Redpanda is said
# so while the operator can still answer no. Warns, never refuses: a staging
# box with 3 GB can run Redpanda in dev mode, it just should not run it as
# configured for production.
broker_resource_check() {
    _memkb=$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)
    _p=/var/lib/redpanda
    while [ ! -d "$_p" ]; do _p=$(dirname "$_p"); done
    _diskkb=$(df -Pk "$_p" 2>/dev/null | awk 'NR == 2 { print $4 }' || true)
    _lowmem=no; _lowdisk=no
    if [ -n "$_memkb" ] && [ "$_memkb" -lt $((BROKER_MIN_MEM_MB * 1024)) ] 2>/dev/null; then _lowmem=yes; fi
    if [ -n "$_diskkb" ] && [ "$_diskkb" -lt $((BROKER_MIN_DISK_GB * 1024 * 1024)) ] 2>/dev/null; then _lowdisk=yes; fi
    [ "$_lowmem" = yes ] || [ "$_lowdisk" = yes ] || return 0

    _memgb=$(awk -v k="${_memkb:-0}" 'BEGIN { printf "%.1f", k / 1048576 }')
    _diskgb=$(awk -v k="${_diskkb:-0}" 'BEGIN { printf "%.1f", k / 1048576 }')
    say ""
    say "  WARNING: this host is small for Redpanda in production mode."
    if [ "$_lowmem" = yes ]; then
        say "    MemAvailable is $_memgb GB; Redpanda wants $((BROKER_MIN_MEM_MB / 1024)) GB or more."
    fi
    if [ "$_lowdisk" = yes ]; then
        say "    $_p has $_diskgb GB free (where /var/lib/redpanda lives); Redpanda wants $BROKER_MIN_DISK_GB GB or more."
    fi
    say "    Redpanda sizes itself to the machine -- a shard per core, most of the RAM taken"
    say "    up front -- and on a small VM it fails to start or starves the rest of the box."
    say "    Either:"
    say "      * Apache Kafka instead, one JVM with a fixed heap:"
    say "          --broker kafka [--kafka-heap 512m] [--kafka-partition-cap 256]"
    say "      * or Redpanda in dev mode on one core and 1 GB, after this script finishes:"
    say "          rpk redpanda mode dev"
    say "          rpk redpanda config set rpk.additional_start_flags '[--smp=1, --memory=1G]'"
    say "          systemctl restart redpanda"
    say "        Dev mode skips fsync: fine for staging, not for billable traffic."
}

# Redpanda: a Kafka-protocol broker in one binary, which is why it is the
# default. The gateway speaks the Kafka protocol and nothing Redpanda-specific,
# so Apache Kafka is equally valid -- --broker kafka installs a single node,
# and a cluster you already run needs nothing from this script at all.
#
# Ships as a deb or rpm for amd64 (x86_64) and arm64 (aarch64) and nothing
# else, so the architecture is checked before the repository is added.
do_redpanda() {
    step "Redpanda"
    case $OS_ARCH in
        amd64|x86_64|arm64|aarch64) ;;
        *) die "Redpanda publishes packages for amd64 and arm64 only, and this host is $OS_ARCH.
            Use --broker kafka, or put the broker on another machine and point the gateway at it
            with --kafka-bootstrap." ;;
    esac

    broker_address
    if [ -n "$SEED_IPS" ]; then
        case ",$SEED_IPS," in
            *",$ADVERTISE_IP,"*) ;;
            *) die "--ips $SEED_IPS does not include this node's own address $ADVERTISE_IP.
                The list is every node of the cluster, this one included." ;;
        esac
    fi

    if have_host rpk && pkg_installed redpanda; then
        _have=$(rpk version 2>/dev/null | head -1 | sed 's/^[^0-9]*//')
        say "   redpanda is already installed (${_have:-version unknown}). Leaving its configuration alone."
        say "   To re-point it: rpk redpanda config bootstrap --self $ADVERTISE_IP${SEED_IPS:+ --ips $SEED_IPS}"
        BROKER_RESULT="redpanda, present${_have:+, $_have}"
        return 0
    fi

    # The vendor's repository script writes the apt source and key for this
    # codename, or on a dnf host the /etc/yum.repos.d entry and its key -- the
    # same vendor, the same host, a different script. It is fetched over TLS
    # from the vendor's own host; the -1 asks curl for TLS 1.x and -f makes a
    # 404 a failure rather than an empty script fed to a shell. We already run
    # as root, so the 'sudo -E bash' of the vendor's instructions is plain
    # 'bash'. Read it first if you like:
    #   curl -1sLf "$REDPANDA_REPO_SETUP" | less       (or $REDPANDA_RPM_SETUP)
    if [ "$PKG" = dnf ]; then _setup=$REDPANDA_RPM_SETUP; else _setup=$REDPANDA_REPO_SETUP; fi
    say "   Adding the Redpanda $PKG repository ($OS_NAME, $OS_ARCH)."
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: curl -1sLf '$_setup' | bash"
    else
        curl -1sLf "$_setup" | bash >/dev/null
    fi
    if [ "$PKG" = dnf ]; then
        run dnf -y -q install "redpanda${REDPANDA_VERSION:+-$REDPANDA_VERSION}"
    else
        run apt-get install -y -qq "redpanda${REDPANDA_VERSION:+=$REDPANDA_VERSION}"
    fi

    # Production mode turns developer_mode off (it is ON in the fresh deb,
    # which among other things makes the node skip fsync and is not what a
    # queue of billable messages wants). The tuner sets kernel knobs that a
    # VM's hypervisor often will not let it; failing there is normal and
    # Redpanda runs fine without them, so it is reported and stepped over.
    run rpk redpanda mode production
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: rpk redpanda tune all   (failure ignored: VMs refuse some tunings)"
    elif ! rpk redpanda tune all >/dev/null 2>&1; then
        say "   rpk redpanda tune all: some tunings refused (normal in a VM). Continuing."
    fi

    # bootstrap writes node_id, the advertised Kafka and RPC addresses and the
    # seed list into /etc/redpanda/redpanda.yaml. On a single node the seeds
    # are itself and an empty seed list is allowed to start a cluster; with
    # --ips every node gets the same three seeds and the "empty seeds start a
    # cluster" shortcut is turned OFF -- otherwise a node that comes up before
    # it can see its peers founds a cluster of its own, and you have three.
    if [ -n "$SEED_IPS" ]; then
        run rpk redpanda config bootstrap --self "$ADVERTISE_IP" --ips "$SEED_IPS"
        run rpk redpanda config set redpanda.empty_seed_starts_cluster false
    else
        run rpk redpanda config bootstrap --self "$ADVERTISE_IP"
    fi
    service_enable redpanda

    # Proving it is up, not just enabled. The first start formats the data
    # directory and elects a controller, so a few seconds of refusal are normal.
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: rpk cluster info"
    elif have_systemd; then
        _tries=0
        until rpk cluster info -X brokers="$ADVERTISE_IP:9092" >/dev/null 2>&1; do
            _tries=$((_tries + 1))
            if [ "$_tries" -ge 15 ]; then
                say "   rpk cluster info did not answer after 30s. 'journalctl -u redpanda' has the reason."
                say "   With --ips this is expected until the other nodes are up."
                break
            fi
            sleep 2
        done
        if [ "$_tries" -lt 15 ]; then say "   Cluster answers on $ADVERTISE_IP:9092."; fi
    fi
    _ver=$(rpk version 2>/dev/null | head -1 | sed 's/^[^0-9]*//')
    BROKER_RESULT="redpanda, installed${_ver:+, $_ver}, advertising $ADVERTISE_IP${SEED_IPS:+, seeds $SEED_IPS}"
    say "   Installed and enabled. No user, ACL or SASL was configured -- see the summary."
}

# ---------------------------------------------------------------------------
# Apache Kafka (--broker kafka)
# ---------------------------------------------------------------------------
# One node in KRaft mode: the same JVM is the controller (the metadata quorum,
# on 127.0.0.1:9093, which nothing outside this host can reach) and the broker
# (the Kafka API the gateways use, 9092). From the apache.org tarball, not a
# package: neither family packages a current Kafka, and a third-party repo for
# one would be worse than a checksummed tarball. Everything below is
# idempotent step by step -- unpacked, user, directories, config, storage
# format, unit -- so a re-run after a failure picks up where it stopped, and a
# re-run on a working broker changes nothing.

java_major() {
    have_host java || return 0
    java -version 2>&1 | head -1 | sed 's/[^0-9]*\([0-9]*\).*/\1/'
}

# The JDK that 'java' resolves to, for the unit: systemd's PATH is not root's,
# and a JDK found on root's PATH (an /opt install, sdkman) is not on it.
java_home() {
    _j=$(command -v java 2>/dev/null || true)
    [ -n "$_j" ] || return 0
    _j=$(readlink -f "$_j" 2>/dev/null || echo "$_j")
    echo "${_j%/bin/java}"
}

# Apache's .sha512 is 'gpg --print-md' output: "name: HEX HEX ..." in upper-case
# groups wrapped across lines. Some releases use sha512sum's "hex  name"
# instead. Both are reduced to 128 lower-case hex characters.
sha512_from_file() {
    _raw=$(cat "$1")
    case $_raw in
        *:*) _raw=${_raw#*:} ;;
        *)   _raw=$(echo "$_raw" | awk '{ print $1; exit }') ;;
    esac
    echo "$_raw" | tr -d ' \t\r\n' | tr 'ABCDEF' 'abcdef'
}

kafka_fetch() {
    _tgz=kafka_$KAFKA_SCALA-$KAFKA_VERSION.tgz
    if [ "$DRY_RUN" = yes ]; then
        _first=${KAFKA_MIRRORS%% *}
        say "   would download $_first/$KAFKA_VERSION/$_tgz"
        say "     and $_tgz.sha512 beside it (archive.apache.org if downloads.apache.org has dropped $KAFKA_VERSION)"
        say "   would verify the SHA-512, then unpack into $KAFKA_HOME"
        return 0
    fi
    have sha512sum || die "no sha512sum; cannot verify the Kafka tarball, so not installing it."
    _tmp=$(mktemp -d)
    _from=""
    for _base in $KAFKA_MIRRORS; do
        if curl -fsSL -o "$_tmp/$_tgz" "$_base/$KAFKA_VERSION/$_tgz" &&
           curl -fsSL -o "$_tmp/$_tgz.sha512" "$_base/$KAFKA_VERSION/$_tgz.sha512"; then
            _from=$_base; break
        fi
    done
    if [ -z "$_from" ]; then
        rm -rf "$_tmp"
        die "could not download Kafka $KAFKA_VERSION ($_tgz) from downloads.apache.org or
            archive.apache.org. Check KAFKA_VERSION is a released x.y.z, and outbound HTTPS."
    fi
    _want=$(sha512_from_file "$_tmp/$_tgz.sha512")
    _got=$(sha512sum "$_tmp/$_tgz" | awk '{ print $1 }')
    if [ "${#_want}" -ne 128 ]; then
        rm -rf "$_tmp"
        die "$_tgz.sha512 from $_from is not a SHA-512 this script can read. Not installing."
    fi
    if [ "$_want" != "$_got" ]; then
        rm -rf "$_tmp"
        die "SHA-512 MISMATCH for $_tgz from $_from.
              expected $_want
              got      $_got
            Not installing. Download it again; if it still differs, do not use it."
    fi
    say "   SHA-512 verified ($_from/$KAFKA_VERSION/$_tgz)."

    # Unpacked in a staging directory BESIDE the destination, not in /tmp: a
    # file created in /opt takes /opt's SELinux label, while one moved from
    # /tmp keeps tmp's, which systemd may then refuse to execute. Same
    # filesystem, so the final mv is a rename.
    _parent=$(dirname "$KAFKA_HOME")
    mkdir -p "$_parent"
    _stage=$(mktemp -d "$_parent/.kafka-unpack.XXXXXX")
    tar -xzf "$_tmp/$_tgz" -C "$_stage" --no-same-owner
    rm -rf "$_tmp"
    _top="$_stage/kafka_$KAFKA_SCALA-$KAFKA_VERSION"
    [ -x "$_top/bin/kafka-server-start.sh" ] || { rm -rf "$_stage"; die "$_tgz did not unpack to the expected kafka_$KAFKA_SCALA-$KAFKA_VERSION/bin."; }
    if [ -e "$KAFKA_HOME" ]; then
        rmdir "$KAFKA_HOME" 2>/dev/null || {
            rm -rf "$_stage"
            die "$KAFKA_HOME exists, is not empty, and has no bin/kafka-server-start.sh.
            Not unpacking over it. Move it aside or pass --kafka-home."
        }
    fi
    mv "$_top" "$KAFKA_HOME"
    rmdir "$_stage"
    say "   Unpacked into $KAFKA_HOME."
}

kafka_properties() {
    # role all: one box, the Kafka API on loopback like the database. broker:
    # every interface, and the firewall decides who reaches it.
    if [ "$ROLE" = all ]; then _bind=127.0.0.1; else _bind=0.0.0.0; fi
    # Segments of a quarter of the cap (16 MB to 1 GB): retention deletes whole
    # segments only, so with Kafka's default 1 GB segment a 1 GB cap would let
    # a partition reach 2 GB before anything went.
    _seg=$((KAFKA_PARTITION_CAP_MB / 4))
    if [ "$_seg" -lt 16 ]; then _seg=16; fi
    if [ "$_seg" -gt 1024 ]; then _seg=1024; fi
    cat <<EOF
# Apache Kafka $KAFKA_VERSION, single node, KRaft. Written by FireFlo setup.sh,
# and never overwritten by it: edit freely, then 'systemctl restart kafka'.

# One process is both the metadata controller and the broker.
process.roles=broker,controller
node.id=1
controller.quorum.bootstrap.servers=127.0.0.1:9093
controller.listener.names=CONTROLLER

# 9092 the Kafka API (gateways); 9093 the controller, loopback only.
listeners=PLAINTEXT://$_bind:9092,CONTROLLER://127.0.0.1:9093
advertised.listeners=PLAINTEXT://$ADVERTISE_IP:9092,CONTROLLER://127.0.0.1:9093
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
inter.broker.listener.name=PLAINTEXT

# One node: every internal topic has one replica, or it is never created.
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
share.coordinator.state.topic.replication.factor=1
share.coordinator.state.topic.min.isr=1
default.replication.factor=1
min.insync.replicas=1

# Topics are created on purpose, not by the first client to mistype a name.
auto.create.topics.enable=false
num.partitions=6

log.dirs=$KAFKA_DATA/data
# Per partition: whichever of 168 hours or $KAFKA_PARTITION_CAP_MB MB comes first.
log.retention.hours=168
log.retention.bytes=$((KAFKA_PARTITION_CAP_MB * 1048576))
log.segment.bytes=$((_seg * 1048576))
log.retention.check.interval.ms=300000
EOF
}

kafka_unit() {
    _jh=$(java_home)
    if [ "$DRY_RUN" = yes ] && { [ -z "$_jh" ] || [ "$FORCED_OS" = yes ]; }; then _jh='<the JDK that java resolves to>'; fi
    cat <<EOF
# Apache Kafka (KRaft, single node), written by FireFlo setup.sh.
[Unit]
Description=Apache Kafka $KAFKA_VERSION (KRaft, single node)
Documentation=https://kafka.apache.org/documentation/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment=JAVA_HOME=$_jh
Environment="KAFKA_HEAP_OPTS=-Xms$KAFKA_HEAP -Xmx$KAFKA_HEAP"
Environment=LOG_DIR=$KAFKA_LOG_DIR
ExecStart=$KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_CONF_DIR/server.properties
Restart=on-failure
RestartSec=5
# The JVM exits 143 on the SIGTERM systemd stops it with; that is a clean stop.
SuccessExitStatus=143
TimeoutStopSec=120
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
}

do_kafka() {
    step "Apache Kafka $KAFKA_VERSION (KRaft, single node)"
    broker_address
    _conf=$KAFKA_CONF_DIR/server.properties
    _unit=/etc/systemd/system/kafka.service

    # 1. the binaries
    if [ "$FORCED_OS" != yes ] && [ -x "$KAFKA_HOME/bin/kafka-server-start.sh" ]; then
        KAFKA_FOUND=$(ls "$KAFKA_HOME"/libs/kafka_*.jar 2>/dev/null |
            sed -n 's#.*/kafka_[0-9.]*-\([0-9][0-9.]*\)\.jar$#\1#p' | head -1)
        say "   Kafka ${KAFKA_FOUND:-of unknown version} is already unpacked at $KAFKA_HOME. Leaving it alone."
        if [ "${KAFKA_FOUND:-}" != "$KAFKA_VERSION" ]; then
            say "   (KAFKA_VERSION is $KAFKA_VERSION; this script does not upgrade an unpacked Kafka.)"
        fi
    else
        kafka_fetch
        KAFKA_FOUND=$KAFKA_VERSION
    fi

    # 2. the user it runs as: no login, no home of its own beyond the data.
    if [ "$FORCED_OS" != yes ] && getent passwd kafka >/dev/null 2>&1; then
        say "   User kafka exists."
    else
        _nologin=$(command -v nologin 2>/dev/null || echo /usr/sbin/nologin)
        if [ "$FORCED_OS" != yes ] && getent group kafka >/dev/null 2>&1; then _grp="--gid kafka"; else _grp="--user-group"; fi
        # shellcheck disable=SC2086
        run useradd --system $_grp --home-dir "$KAFKA_DATA" --no-create-home --shell "$_nologin" kafka
    fi

    # 3. directories. The data and log directories are the broker's; the
    # binaries and the config stay root's.
    run mkdir -p "$KAFKA_DATA/data" "$KAFKA_LOG_DIR" "$KAFKA_CONF_DIR"
    run chown kafka:kafka "$KAFKA_DATA" "$KAFKA_DATA/data" "$KAFKA_LOG_DIR"
    run chmod 750 "$KAFKA_DATA"

    # 4. the config -- written only when absent, so an operator's edits survive
    # a re-run. log.dirs is read back from it for the format check.
    if [ "$FORCED_OS" != yes ] && [ -f "$_conf" ]; then
        say "   $_conf exists. Leaving it alone (move it aside and re-run to regenerate)."
    else
        kafka_properties | write_file "$_conf" 644
    fi
    _logdir="$KAFKA_DATA/data"
    if [ "$DRY_RUN" != yes ] && [ -f "$_conf" ]; then
        _ld=$(sed -n 's/^[[:space:]]*log\.dirs[[:space:]]*=[[:space:]]*//p' "$_conf" | tail -1 | cut -d, -f1)
        _logdir=${_ld:-$_logdir}
    fi

    # 5. format the storage -- once. meta.properties is what format writes; its
    # presence means a cluster id already exists here, and formatting again
    # would refuse (or, forced, throw away the data).
    if [ "$FORCED_OS" != yes ] && [ -f "$_logdir/meta.properties" ]; then
        say "   $_logdir is already formatted (meta.properties present)."
    elif [ "$DRY_RUN" = yes ]; then
        say "   would run: $KAFKA_HOME/bin/kafka-storage.sh format --standalone -t <kafka-storage.sh random-uuid> -c $_conf"
        say "   would run: chown -R kafka:kafka $_logdir $KAFKA_LOG_DIR"
    else
        _cid=$("$KAFKA_HOME/bin/kafka-storage.sh" random-uuid)
        LOG_DIR=$KAFKA_LOG_DIR "$KAFKA_HOME/bin/kafka-storage.sh" format --standalone -t "$_cid" -c "$_conf" >/dev/null
        chown -R kafka:kafka "$_logdir" "$KAFKA_LOG_DIR"
        say "   Formatted $_logdir (cluster id $_cid)."
    fi

    # 6. the unit, also written only when absent.
    if [ "$FORCED_OS" != yes ] && [ -f "$_unit" ]; then
        say "   $_unit exists. Leaving it alone."
    else
        kafka_unit | write_file "$_unit" 644
        if [ "$DRY_RUN" = yes ]; then
            say "   would run: systemctl daemon-reload"
        elif have_systemd; then
            systemctl daemon-reload
        fi
    fi
    service_enable kafka

    # 7. proof it answers. A JVM start plus the first controller election takes
    # several seconds, so 30 of retries before saying anything is wrong.
    _bs=127.0.0.1:9092
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: $KAFKA_HOME/bin/kafka-topics.sh --bootstrap-server $_bs --list   (retried for 30s)"
    elif have_systemd; then
        _deadline=$(( $(date +%s) + 30 )); _ok=no
        while [ "$(date +%s)" -lt "$_deadline" ]; do
            if timeout 15 "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$_bs" --list >/dev/null 2>&1; then
                _ok=yes; break
            fi
            sleep 2
        done
        if [ "$_ok" = yes ]; then
            say "   Kafka answers on $_bs."
        else
            say "   kafka-topics.sh did not answer within 30s. 'journalctl -u kafka' and $KAFKA_LOG_DIR/server.log have the reason."
        fi
    fi
    BROKER_RESULT="kafka ${KAFKA_FOUND:-$KAFKA_VERSION} (KRaft, one node), advertising $ADVERTISE_IP:9092, config $_conf"
    say "   Installed and enabled. PLAINTEXT, no SASL, no ACLs -- see the summary."
}

do_node() {
    step "Node"
    if have_host node; then
        _have=$(major_of "$(node --version 2>/dev/null)")
        if [ -n "$_have" ] && [ "$_have" -ge "$NODE_MIN_MAJOR" ] 2>/dev/null; then
            say "   Node $_have is already installed. Leaving it alone."
            NODE_RESULT="present, $_have"
            return 0
        fi
        say "   Node $_have is installed and the control panel needs $NODE_MIN_MAJOR or newer."
    fi
    if [ "$PKG" = dnf ]; then do_node_dnf; return 0; fi
    say "   Adding NodeSource for Node $NODE_INSTALL_MAJOR ($OS_NAME)."
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: curl -fsSL https://deb.nodesource.com/setup_$NODE_INSTALL_MAJOR.x | bash -"
    else
        curl -fsSL "https://deb.nodesource.com/setup_$NODE_INSTALL_MAJOR.x" | bash - >/dev/null
    fi
    run apt-get install -y -qq nodejs
    NODE_RESULT="installed, $NODE_INSTALL_MAJOR"
}

# dnf: the distribution's nodejs:22 module stream first -- AppStream, so no
# third-party repository -- and NodeSource's rpm repository only when the
# release has no stream (or default package) at 20 or newer.
do_node_dnf() {
    _ns="https://rpm.nodesource.com/setup_$NODE_INSTALL_MAJOR.x"
    dnf_module_stream nodejs "$NODE_INSTALL_MAJOR"
    _cand=${MOD_STREAM:-$(dnf_candidate_major nodejs)}
    if [ -n "$_cand" ] && [ "$_cand" -ge "$NODE_MIN_MAJOR" ] 2>/dev/null; then
        run dnf -y -q install nodejs
        if [ "$DRY_RUN" = yes ] && ! have dnf; then
            say "   fallback, where the release has no nodejs:$NODE_INSTALL_MAJOR stream or default nodejs $NODE_MIN_MAJOR+:"
            say "     curl -fsSL $_ns | bash -  &&  dnf -y install nodejs"
        fi
        NODE_RESULT="installed, $_cand (distribution)"
        return 0
    fi
    # NodeSource's packages are filtered out by an enabled nodejs stream, so an
    # old stream someone else enabled has to be reset first -- by them.
    if [ "$MOD_PRESET" = yes ]; then
        die "module stream nodejs:$MOD_STREAM is enabled on this host and the panel needs $NODE_MIN_MAJOR or newer.
            Not switching it under whatever installed it. 'dnf module reset -y nodejs' (or
            'dnf module enable nodejs:$NODE_INSTALL_MAJOR') and re-run."
    fi
    say "   No nodejs $NODE_MIN_MAJOR+ from $OS_PRETTY${_cand:+ (it has $_cand)}; adding NodeSource for Node $NODE_INSTALL_MAJOR."
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: curl -fsSL $_ns | bash -"
    else
        curl -fsSL "$_ns" | bash - >/dev/null
    fi
    run dnf -y -q install nodejs
    NODE_RESULT="installed, $NODE_INSTALL_MAJOR (NodeSource)"
}

# The panel reads the gateway's database directly, so it wants psql for the
# same 3am reason the gateway does, and nothing else beyond Node.
do_panel_tools() {
    step "Panel client tools"
    if [ "$PKG" = dnf ]; then
        dnf_pg_client
        TOOLS_RESULT="postgresql${PGC_NOTE:+ ($PGC_NOTE)} curl"
        say "   $TOOLS_RESULT"
        return 0
    fi
    run apt-get install -y -qq postgresql-client curl
    TOOLS_RESULT="postgresql-client curl"
    say "   $TOOLS_RESULT"
}

do_java() {
    step "Java"
    _have=$(java_major)
    if [ -n "$_have" ] && [ "$_have" -ge 25 ] 2>/dev/null; then
        say "   Java $_have is already installed. Leaving it alone."
        JAVA_RESULT="present, $_have"
        return 0
    fi
    if [ "$PKG" = dnf ]; then do_java_dnf; return 0; fi
    say "   Adding Adoptium for Temurin 25 ($OS_NAME)."
    run mkdir -p /etc/apt/keyrings
    if [ "$DRY_RUN" = yes ]; then
        say "   would fetch the Adoptium key into /etc/apt/keyrings/adoptium.asc"
        say "   would write /etc/apt/sources.list.d/adoptium.list for $OS_NAME"
    else
        wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
            > /etc/apt/keyrings/adoptium.asc
        chmod 644 /etc/apt/keyrings/adoptium.asc
        echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $OS_NAME main" \
            > /etc/apt/sources.list.d/adoptium.list
    fi
    run apt-get update -qq
    run apt-get install -y -qq temurin-25-jdk
    JAVA_RESULT="installed, 25"
}

# dnf: Adoptium's rpm repository. $releasever and $basearch are dnf's own
# variables, expanded by dnf at every use -- which is why the file is written
# with them literal. dnf imports the key from gpgkey on the first install
# (that is what -y accepts) and checks every package against it after.
do_java_dnf() {
    _repo=/etc/yum.repos.d/adoptium.repo
    say "   Adding Adoptium for Temurin 25 ($ADOPTIUM_DISTRO/\$releasever/\$basearch)."
    if [ "$FORCED_OS" != yes ] && [ -f "$_repo" ]; then
        say "   $_repo exists. Leaving it alone."
    else
        write_file "$_repo" 644 <<EOF
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/$ADOPTIUM_DISTRO/\$releasever/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF
    fi
    run dnf -y -q install temurin-25-jdk
    JAVA_RESULT="installed, 25"
}

# ---------------------------------------------------------------------------
# notes
# ---------------------------------------------------------------------------
kafka_kraft_notes() {
    cat <<'EOF'
Apache Kafka instead of Redpanda

The gateway speaks the Kafka wire protocol and nothing broker-specific, so
Apache Kafka in KRaft mode (no ZooKeeper) is supported as well as Redpanda.

ONE NODE, from this script:

  sudo ./setup.sh --role broker --broker kafka --with-java      (or --role all)

installs Apache Kafka from the apache.org tarball (SHA-512 checked) under
/opt/kafka, a single KRaft node that is its own controller, with
/etc/kafka/server.properties and a 'kafka' systemd unit. No package manager is
involved, so it is the same on apt and dnf hosts; it needs Java 17 or newer,
which --with-java provides. It is the better choice on a small VM: one JVM
with a fixed heap (--kafka-heap, default 1g) where Redpanda sizes itself to
the whole machine. --kafka-home, --kafka-data and --kafka-partition-cap
adjust it; KAFKA_VERSION picks the release.

A CLUSTER of three brokers this script does not build. Kafka is a JVM
application with its own sizing, its own tuning and usually its own team, and
a script that guessed at the quorum and the replication would be worse than
none. Run one yourself, or have one already, and the gateway needs from it
what it needs from Redpanda:

  * the brokers' addresses, handed to fireflo-install as
      --kafka-bootstrap kafka1:9092,kafka2:9092,kafka3:9092
  * topics prefixed  fireflo.   and consumer groups prefixed  fireflo-  --
    a principal allowed to produce and consume on those prefixes if ACLs are on

The topic list, sizing and the KRaft notes are in the gateway tarball at
docs/21-clustering.md. Redpanda is the default because it is one binary
speaking the same protocol; it is a recommendation, not a requirement.
EOF
}

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
print_allow_lines() {
    # one block per subnet, or one block of placeholders
    _subnets=${ALLOW_FROM:-<gateway-cidr>}
    for _cidr in $_subnets; do
        echo "  host    all             all             $_cidr    scram-sha-256"
    done
}

# Firewall lines, in the dialect of the host's firewall (FW, from detect_host).
# Printed, never run.
fw_intro() {
    if [ "$FW" = firewalld ]; then
        if [ "$FW_ACTIVE" = yes ]; then
            echo "firewalld is running here. This script writes no rules to it; these are the rules:"
        else
            echo "This script writes no firewalld rules (and firewalld is not running here); these"
            echo "are the rules when you start it:"
        fi
    else
        echo "This script does not enable ufw; these are the rules when you do:"
    fi
}

fw_ssh() {
    if [ "$FW" = firewalld ]; then
        echo "  sudo firewall-cmd --permanent --add-service=ssh"
    else
        echo "  sudo ufw allow OpenSSH"
    fi
}

# $1 source address or CIDR, $2 port, $3 what it is for, $4 an optional trailing note
fw_allow() {
    if [ "$FW" = firewalld ]; then
        echo "  sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=$1 port port=$2 protocol=tcp accept'   # $3${4:+ -- $4}"
    else
        echo "  sudo ufw allow from $1 to any port $2 proto tcp comment '$3'${4:+   # $4}"
    fi
}

fw_done() {
    if [ "$FW" = firewalld ]; then echo "  sudo firewall-cmd --reload"; fi
}

print_fw_from() {
    # $1 port, $2 comment, then the subnets or a placeholder
    _port=$1; _what=$2; shift 2
    for _src in "$@"; do
        fw_allow "$_src" "$_port" "$_what"
    done
}

summary_db_commands() {
    cat <<'EOF'

This script created no database. FireFlo needs one, and it is yours to make,
on this host:

  sudo -u postgres createuser --pwprompt fireflo
  sudo -u postgres createdb --owner=fireflo fireflo

Keep that password out of your shell history -- put it in a file and hand
fireflo-install the file, not the value.
EOF
}

summary_db_access() {
    _n='<N>'
    pg_conf_paths
    echo
    if [ -n "$ALLOW_FROM" ]; then
        echo "Gateway access was configured for: $ALLOW_FROM"
        echo "The files edited (originals kept beside them as *.bak.<timestamp>):"
        echo "  $PG_CONF   listen_addresses = '*'"
        echo "  $PG_HBA       the lines below"
    else
        echo "Nothing was edited to let gateways in: no --allow-from was given. The gateway"
        echo "nodes are on another subnet, so the server needs these, and then a restart:"
        echo
        echo "  $PG_CONF:"
        echo "  listen_addresses = '*'"
        echo
        echo "  $PG_HBA:"
    fi
    print_allow_lines
    cat <<EOF

Re-run with --allow-from <cidr> (repeatable) and this script applies them for
you, with a backup of each file.

Size the connection limit for the gateways you will run. Each node opens up to
$PG_CONN_PER_GATEWAY connections and the panel, the sweeps and your own psql want about
$PG_CONN_OVERHEAD more, so for $_n gateway nodes:

  max_connections = $PG_CONN_PER_GATEWAY * $_n + $PG_CONN_OVERHEAD      (1 node: $((PG_CONN_PER_GATEWAY + PG_CONN_OVERHEAD)), 2: $((PG_CONN_PER_GATEWAY * 2 + PG_CONN_OVERHEAD)), 3: $((PG_CONN_PER_GATEWAY * 3 + PG_CONN_OVERHEAD)); the default 100 covers 4)

Firewall: 5432 from the gateway subnet(s) and the panel host, nothing else.
EOF
    fw_intro
    echo
    fw_ssh
    # shellcheck disable=SC2086
    print_fw_from 5432 'PostgreSQL from FireFlo gateways' ${ALLOW_FROM:-<gateway-cidr>}
    fw_allow '<panel-host-ip>' 5432 'PostgreSQL from the control panel'
    fw_done
}

summary_broker_next() {
    if [ "$BROKER" = kafka ]; then summary_kafka_next; return 0; fi
    _bs="${ADVERTISE_IP:-<broker-ip>}:9092"
    cat <<EOF

Redpanda is listening on $_bs with no authentication and no ACLs. On a
single box with 9092 closed to the outside that is fine. On a broker host it is
not: do the firewall first, then the credentials, in this order.

Firewall. 9092 is the Kafka API (gateways), 9644 the admin API (the panel
and monitoring), 33145 the RPC port (the other brokers, and only them).
EOF
    fw_intro
    echo
    fw_ssh
    fw_allow '<gateway-cidr>' 9092 'Kafka API from FireFlo gateways'
    fw_allow '<panel-host-ip>' 9644 'Redpanda admin API from the panel'
    if [ -n "$SEED_IPS" ]; then
        for _peer in $(echo "$SEED_IPS" | tr ',' ' '); do
            if [ "$_peer" = "$ADVERTISE_IP" ]; then continue; fi
            fw_allow "$_peer" 33145 'Redpanda RPC from a peer broker'
            fw_allow "$_peer" 9092 'Kafka API from a peer broker'
        done
    else
        fw_allow '<peer-broker-ip>' 33145 'Redpanda RPC from a peer broker' 'cluster only'
    fi
    fw_done
    cat <<EOF

Credentials. One user for every gateway node, allowed everything on the
'fireflo.' topics and the 'fireflo-' consumer groups and nothing else. Pick
the password yourself and keep it out of your shell history:

  rpk acl user create fireflo -p '<password>'
  rpk acl create --allow-principal User:fireflo --operation all \\
      --topic 'fireflo.*' --resource-pattern-type prefixed
  rpk acl create --allow-principal User:fireflo --operation all \\
      --group 'fireflo-*' --resource-pattern-type prefixed

Then turn authentication on. Name a superuser first -- rpk itself needs one
once SASL is on -- and from then on pass its credentials to rpk:

  rpk acl user create admin -p '<admin-password>'
  rpk cluster config set superusers '["admin"]'
  rpk cluster config set enable_sasl true
  rpk cluster info -X user=admin -X pass='<admin-password>' -X sasl.mechanism=SCRAM-SHA-256

Hand the gateway the bootstrap address at install time, and the fireflo user's
credentials the way 'fireflo-install --help' describes for SASL:

  --kafka-bootstrap $_bs
EOF
    if [ -n "$SEED_IPS" ]; then
        cat <<EOF

This is one node of three. Run this same script on the other two with the same
--ips $SEED_IPS and their own --advertise-ip (pin REDPANDA_VERSION so the three
match). The cluster forms when a majority is up; until then 'rpk cluster info'
refuses, which is correct. Give the gateways all three:

  --kafka-bootstrap $(echo "$SEED_IPS" | sed 's/,/:9092,/g'):9092
EOF
    fi
}

# Where the --broker kafka install lives and how to look at it. Shared by
# --role broker and --role all.
summary_kafka_where() {
    cat <<EOF

  systemctl status kafka
  journalctl -u kafka                  (and $KAFKA_LOG_DIR/server.log)
  config    $KAFKA_CONF_DIR/server.properties
  unit      /etc/systemd/system/kafka.service   (heap -Xmx$KAFKA_HEAP)
  data      $KAFKA_DATA/data   (per partition: 168 h or $KAFKA_PARTITION_CAP_MB MB, whichever first)
  binaries  $KAFKA_HOME
  topics    $KAFKA_HOME/bin/kafka-topics.sh --bootstrap-server 127.0.0.1:9092 --list

auto.create.topics.enable is false, as on Redpanda: the gateway's topics must
exist before it produces to them (docs/21-clustering.md has the list).
EOF
}

summary_kafka_next() {
    _bs="${ADVERTISE_IP:-<broker-ip>}:9092"
    cat <<EOF

Apache Kafka is one KRaft node listening on $_bs, PLAINTEXT, with no
authentication and no ACLs. Its controller is on 127.0.0.1:9093 and nothing
outside this host can reach it.
EOF
    summary_kafka_where
    cat <<EOF

Firewall. 9092 is the Kafka API, for the gateways and nobody else; 9093 is
loopback-only and needs no rule.
EOF
    fw_intro
    echo
    fw_ssh
    fw_allow '<gateway-cidr>' 9092 'Kafka API from FireFlo gateways'
    fw_done
    cat <<EOF

Credentials. This script leaves Kafka on PLAINTEXT: SASL/SCRAM needs a second
listener, an authorizer and a JAAS entry, which is a change to make with the
broker in front of you rather than one to guess at. With 9092 firewalled to
the gateway subnet, PLAINTEXT is the same exposure as an unauthenticated
Redpanda. When you turn it on, the fireflo principal wants everything on the
'fireflo.' topics and the 'fireflo-' groups (prefixed ACLs), as --kafka-kraft-notes
describes.

Hand the gateway the bootstrap address at install time:

  --kafka-bootstrap $_bs
EOF
}

summary_install_all() {
    cat <<'EOF'

Then install the gateway on this host. The broker is local, so bootstrap is
loopback, and this is node gw-1 of a cluster of one:

  sudo ./scripts/fireflo-install install --from ./gateway \
      --config-source db --bootstrap \
      --db-name fireflo --db-user fireflo --db-password-file /root/fireflo-db.pw \
      --kafka-bootstrap 127.0.0.1:9092 --node-id gw-1

Without --kafka-bootstrap the queue is in memory and a restart drops whatever
has not reached a vendor. That is the gateway's default and it is a real trade,
not an oversight.
EOF
}

summary_install_gateway() {
    cat <<'EOF'

Nothing on this host holds state. Install the gateway against the database and
broker hosts -- the first node runs the migrations and bootstraps the config:

  sudo ./scripts/fireflo-install install --from ./gateway --role gateway \
      --config-source db --bootstrap \
      --db-host <db-ip> --db-name fireflo --db-user fireflo --db-password-file /root/fireflo-db.pw \
      --kafka-bootstrap <broker-ip>:9092 --node-id gw-1

Every further node joins instead, with its own id and WITHOUT running the
migrations, which the first node already did:

  sudo ./scripts/fireflo-install install --from ./gateway --role gateway \
      --config-source db --join --no-migrate \
      --db-host <db-ip> --db-name fireflo --db-user fireflo --db-password-file /root/fireflo-db.pw \
      --kafka-bootstrap <broker-ip>:9092 --node-id gw-2

Firewall, this host. Outbound: 5432 to the database host, 9092 to every
broker. Inbound: the customer-facing SMPP listener (2775 by default, or the
band fireflo-install is given), the HTTP API (8080) from wherever your
customers and load balancer are, and the management port (9000) from the panel
host ONLY -- it is bound to loopback until fireflo-install is told otherwise.
EOF
    if [ "$FW" = firewalld ]; then
        echo "'fireflo-install --firewall' writes ufw rules only, so on this host all of these are yours."
    else
        echo "'fireflo-install --firewall' writes the inbound SMPP and HTTP rules; the rest are yours."
    fi
    fw_intro
    echo
    fw_ssh
    fw_allow '<customer-or-lb-cidr>' 2775 'SMPP'
    fw_allow '<customer-or-lb-cidr>' 8080 'FireFlo HTTP API'
    fw_allow '<panel-host-ip>' 9000 'FireFlo management from the panel'
    fw_done
}

summary_install_panel() {
    cat <<'EOF'

Install the control panel from the tarball's panel/ directory:

  sudo ./panel/scripts/fireflo-panel-install install

On a host of its own there is no /etc/fireflo for the installer to read the
database connection from (that is what --gateway-conf-dir does on a one-box
install), so it will ask for the database host, name, user and password file,
and for the address of a gateway's management port (9000), which the panel
reaches over HMAC. 'fireflo-panel-install --help' lists the flags; the README,
"Install the control panel", covers the reverse proxy in front of it.

Firewall, this host: inbound 443 (and 80, if you redirect it) from your
admins; outbound 5432 to the database host and 9000 to each gateway node.
EOF
}

summary() {
    step "Done"
    printf '  %-12s %s\n' "host"       "$OS_PRETTY ($OS_NAME, $OS_ARCH, $PKG)"
    printf '  %-12s %s\n' "role"       "$ROLE"
    printf '  %-12s %s\n' "postgresql" "${PG_RESULT:-skipped}"
    if [ -n "${PG_ACCESS_RESULT:-}" ]; then printf '  %-12s %s\n' "pg access" "$PG_ACCESS_RESULT"; fi
    printf '  %-12s %s\n' "broker"     "${BROKER_RESULT:-skipped}"
    printf '  %-12s %s\n' "node"       "${NODE_RESULT:-skipped}"
    printf '  %-12s %s\n' "tools"      "${TOOLS_RESULT:-skipped}"
    printf '  %-12s %s\n' "java"       "${JAVA_RESULT:-not installed -- the gateway is native and needs none}"
    if [ "$PKG" = dnf ]; then
        _se=$(selinux_mode)
        if [ "$FORCED_OS" = yes ]; then _se_none="not checked (simulated host)"; else _se_none="not checked (no getenforce)"; fi
        printf '  %-12s %s\n' "selinux" "${_se:-$_se_none}${_se:+ -- read, not changed}"
    fi

    case $ROLE in
        all)
            if [ "$WITH_POSTGRES" = yes ]; then summary_db_commands; fi
            if [ -n "${BROKER_RESULT:-}" ] && [ "$BROKER" = kafka ]; then
                cat <<'EOF'

Apache Kafka is a single KRaft node on 127.0.0.1:9092 -- bound to loopback, so
nothing outside this host reaches it -- with no authentication. Add a second
gateway node later and the broker must listen beyond loopback: change
listeners and advertised.listeners in the config below to this host's address,
restart it, and firewall 9092 to the gateways.
EOF
                summary_kafka_where
            elif [ -n "${BROKER_RESULT:-}" ]; then
                cat <<'EOF'

Redpanda is a single node on 127.0.0.1:9092 with no authentication. Port 9092 is
not reachable from outside this host unless you open it, so that is fine here.
Add a second gateway node later and the broker needs the --role broker
treatment: 'rpk redpanda config bootstrap --self <this-ip>' and the ACL and
SASL steps that --role broker prints.
EOF
            fi
            summary_install_all
            ;;
        db)
            summary_db_commands
            summary_db_access
            ;;
        broker)
            summary_broker_next
            ;;
        gateway)
            summary_install_gateway
            ;;
        panel)
            summary_install_panel
            ;;
    esac
    selinux_notes

    cat <<'EOF'

Then check the host before installing anything:

  ./scripts/fireflo-install check

Full documentation: https://docs.fireflo.au  (multi-host: README, "Multi-host and clustering")
EOF
}

# ---------------------------------------------------------------------------
# options
# ---------------------------------------------------------------------------
NO_NODE_GIVEN=no
NO_PG_GIVEN=no
BROKER_GIVEN=no
KAFKA_OPT_GIVEN=no
while [ $# -gt 0 ]; do
    case $1 in
        --role)        [ $# -ge 2 ] || die "--role needs a value: all|gateway|db|broker|panel"
                       ROLE=$2; shift 2 ;;
        --role=*)      ROLE=${1#--role=}; shift ;;
        --allow-from)  [ $# -ge 2 ] || die "--allow-from needs a CIDR, e.g. 10.0.1.0/24"
                       looks_like_cidr "$2" || die "--allow-from '$2' is not a.b.c.d/nn. A bare address is a.b.c.d/32."
                       ALLOW_FROM="${ALLOW_FROM:+$ALLOW_FROM }$2"; shift 2 ;;
        --allow-from=*) _v=${1#--allow-from=}
                       looks_like_cidr "$_v" || die "--allow-from '$_v' is not a.b.c.d/nn. A bare address is a.b.c.d/32."
                       ALLOW_FROM="${ALLOW_FROM:+$ALLOW_FROM }$_v"; shift ;;
        --advertise-ip) [ $# -ge 2 ] || die "--advertise-ip needs an address"
                       looks_like_ip "$2" || die "--advertise-ip '$2' is not an IPv4 address."
                       ADVERTISE_IP=$2; shift 2 ;;
        --advertise-ip=*) ADVERTISE_IP=${1#--advertise-ip=}
                       looks_like_ip "$ADVERTISE_IP" || die "--advertise-ip '$ADVERTISE_IP' is not an IPv4 address."
                       shift ;;
        --ips)         [ $# -ge 2 ] || die "--ips needs a comma-separated list of the cluster's addresses"
                       SEED_IPS=$2; shift 2 ;;
        --ips=*)       SEED_IPS=${1#--ips=}; shift ;;
        --broker)      [ $# -ge 2 ] || die "--broker needs a value: redpanda|kafka"
                       BROKER=$2; BROKER_GIVEN=yes; shift 2 ;;
        --broker=*)    BROKER=${1#--broker=}; BROKER_GIVEN=yes; shift ;;
        --kafka-home)  [ $# -ge 2 ] || die "--kafka-home needs a directory"
                       KAFKA_HOME=$2; KAFKA_OPT_GIVEN=yes; shift 2 ;;
        --kafka-home=*) KAFKA_HOME=${1#--kafka-home=}; KAFKA_OPT_GIVEN=yes; shift ;;
        --kafka-data)  [ $# -ge 2 ] || die "--kafka-data needs a directory"
                       KAFKA_DATA=$2; KAFKA_OPT_GIVEN=yes; shift 2 ;;
        --kafka-data=*) KAFKA_DATA=${1#--kafka-data=}; KAFKA_OPT_GIVEN=yes; shift ;;
        --kafka-heap)  [ $# -ge 2 ] || die "--kafka-heap needs a size, e.g. 1g or 512m"
                       KAFKA_HEAP=$2; KAFKA_OPT_GIVEN=yes; shift 2 ;;
        --kafka-heap=*) KAFKA_HEAP=${1#--kafka-heap=}; KAFKA_OPT_GIVEN=yes; shift ;;
        --kafka-partition-cap) [ $# -ge 2 ] || die "--kafka-partition-cap needs a size in MB"
                       KAFKA_PARTITION_CAP_MB=$2; KAFKA_OPT_GIVEN=yes; shift 2 ;;
        --kafka-partition-cap=*) KAFKA_PARTITION_CAP_MB=${1#--kafka-partition-cap=}; KAFKA_OPT_GIVEN=yes; shift ;;
        --with-java)   WITH_JAVA=yes; shift ;;
        --no-node)     WITH_NODE=no; NO_NODE_GIVEN=yes; shift ;;
        --no-postgres) WITH_POSTGRES=no; NO_PG_GIVEN=yes; shift ;;
        # Recognised so that a 0.13 runbook fails on its first line with the
        # reason, rather than on 'unknown option' with none.
        --no-rabbitmq) die "RabbitMQ is no longer part of FireFlo (removed in 0.14). This script now installs Redpanda (or, with --broker kafka, Apache Kafka) for --role broker|all; see README 'Multi-host and clustering'." ;;
        --kafka-kraft-notes) kafka_kraft_notes; exit 0 ;;
        --dry-run)     DRY_RUN=yes; shift ;;
        --yes|-y)      ASSUME_YES=yes; shift ;;
        --help|-h)     usage 0 ;;
        *) echo "setup.sh: unknown option '$1'" >&2; usage 1 ;;
    esac
done

case $ROLE in
    all|gateway|db|broker|panel) ;;
    *) die "--role '$ROLE' is not one of all, gateway, db, broker, panel." ;;
esac

# Options that only mean something for one role are refused elsewhere rather
# than ignored: an ignored --allow-from on a gateway host would leave the
# operator believing the database was opened.
if [ "$ROLE" != all ] && { [ "$NO_NODE_GIVEN" = yes ] || [ "$NO_PG_GIVEN" = yes ]; }; then
    die "--no-node and --no-postgres only apply to --role all; --role $ROLE already installs neither
            or needs it. Drop the flag."
fi
if [ -n "$ALLOW_FROM" ] && [ "$ROLE" != db ]; then
    die "--allow-from is for --role db. A --role all host keeps PostgreSQL on loopback; open it by
            hand if a second gateway node ever needs in."
fi
case $BROKER in
    redpanda|kafka) ;;
    *) die "--broker '$BROKER' is not redpanda or kafka." ;;
esac
if [ "$BROKER_GIVEN" = yes ] && [ "$ROLE" != broker ] && [ "$ROLE" != all ]; then
    die "--broker is for --role broker or --role all; --role $ROLE installs no broker."
fi
if [ "$KAFKA_OPT_GIVEN" = yes ] && [ "$BROKER" != kafka ]; then
    die "--kafka-home, --kafka-data, --kafka-heap and --kafka-partition-cap are for --broker kafka."
fi
if [ "$BROKER" = kafka ]; then
    [ -z "$SEED_IPS" ] || die "--ips builds a Redpanda cluster. --broker kafka installs ONE node; a Kafka
            cluster is yours to build (--kafka-kraft-notes)."
    case $KAFKA_HOME in /*) ;; *) die "--kafka-home '$KAFKA_HOME' is not an absolute path." ;; esac
    case $KAFKA_DATA in /*) ;; *) die "--kafka-data '$KAFKA_DATA' is not an absolute path." ;; esac
    case $KAFKA_HOME in /|/usr|/opt|/etc|/var) die "--kafka-home $KAFKA_HOME: name a directory of its own, e.g. /opt/kafka." ;; esac
    echo "$KAFKA_HEAP" | grep -Eq '^[1-9][0-9]*[mMgG]$' ||
        die "--kafka-heap '$KAFKA_HEAP' is not a JVM size like 512m or 1g."
    echo "$KAFKA_PARTITION_CAP_MB" | grep -Eq '^[1-9][0-9]*$' && [ "$KAFKA_PARTITION_CAP_MB" -ge 64 ] ||
        die "--kafka-partition-cap '$KAFKA_PARTITION_CAP_MB' is not a size in MB of 64 or more."
    echo "$KAFKA_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
        die "KAFKA_VERSION '$KAFKA_VERSION' is not a release number like 4.4.0."
fi
if [ -n "$SEED_IPS" ] && [ "$ROLE" != broker ]; then
    die "--ips is for --role broker. --role all runs a single node on 127.0.0.1."
fi
if [ -n "$ADVERTISE_IP" ] && [ "$ROLE" != broker ]; then
    die "--advertise-ip is for --role broker. --role all runs a single node on 127.0.0.1."
fi
if [ -n "$SEED_IPS" ]; then
    _n=$(echo "$SEED_IPS" | tr ',' '\n' | grep -c .)
    [ "$_n" -eq 3 ] || die "--ips lists $_n addresses; a Redpanda cluster here is exactly three. One node needs no --ips."
    for _seed in $(echo "$SEED_IPS" | tr ',' ' '); do
        looks_like_ip "$_seed" || die "--ips: '$_seed' is not an IPv4 address."
    done
    # Caught here when the address is given, so the refusal comes before the
    # "Proceed?" prompt; do_redpanda repeats the check for the auto-detected one.
    if [ -n "$ADVERTISE_IP" ]; then
        case ",$SEED_IPS," in
            *",$ADVERTISE_IP,"*) ;;
            *) die "--ips $SEED_IPS does not include this node's own --advertise-ip $ADVERTISE_IP.
            The list is every node of the cluster, this one included." ;;
        esac
    fi
fi

# What each role installs. Spelled out as a table rather than scattered through
# the steps, so that the plan the operator confirms below is the plan that runs.
case $ROLE in
    all)     DO_PG=$WITH_POSTGRES; DO_PG_ACCESS=no;  DO_BROKER=yes; DO_NODE=$WITH_NODE; DO_GW_TOOLS=yes; DO_PANEL_TOOLS=no ;;
    gateway) DO_PG=no;             DO_PG_ACCESS=no;  DO_BROKER=no;  DO_NODE=no;         DO_GW_TOOLS=yes; DO_PANEL_TOOLS=no ;;
    db)      DO_PG=yes;            DO_PG_ACCESS=yes; DO_BROKER=no;  DO_NODE=no;         DO_GW_TOOLS=no;  DO_PANEL_TOOLS=no ;;
    broker)  DO_PG=no;             DO_PG_ACCESS=no;  DO_BROKER=yes; DO_NODE=no;         DO_GW_TOOLS=no;  DO_PANEL_TOOLS=no ;;
    panel)   DO_PG=no;             DO_PG_ACCESS=no;  DO_BROKER=no;  DO_NODE=yes;        DO_GW_TOOLS=no;  DO_PANEL_TOOLS=yes ;;
esac

detect_host

[ "$DRY_RUN" = yes ] || [ "$(id -u)" = 0 ] ||
    die "run this as root: sudo ./setup.sh   (or --dry-run to see what it would do)"

# Kafka is a JVM. Refused here, before the prompt and before anything is
# installed, rather than after a tarball is unpacked that cannot start.
if [ "$DO_BROKER" = yes ] && [ "$BROKER" = kafka ] && [ "$WITH_JAVA" = no ]; then
    _jv=$(java_major)
    if [ -z "$_jv" ] || [ "$_jv" -lt "$KAFKA_JAVA_MIN" ] 2>/dev/null; then
        die "--broker kafka needs Java $KAFKA_JAVA_MIN or newer, and this host has ${_jv:+only Java }${_jv:-no java}.
            Add --with-java (Temurin 25, from Adoptium), or install a JDK $KAFKA_JAVA_MIN+ yourself and re-run."
    fi
fi

say "FireFlo host setup"
say "  host        $OS_PRETTY ($OS_NAME, $OS_ARCH, $PKG)"
say "  role        $ROLE"
say "  postgresql  $([ "$DO_PG" = yes ] && echo "yes, $PG_MIN_MAJOR+" || echo skip)"
if [ "$DO_PG_ACCESS" = yes ]; then
    say "  pg access   $([ -n "$ALLOW_FROM" ] && echo "open to $ALLOW_FROM (edits postgresql.conf and pg_hba.conf, with backups)" || echo "print the lines only -- no --allow-from")"
fi
if [ "$DO_BROKER" = yes ] && [ "$BROKER" = kafka ]; then
    say "  broker      kafka $KAFKA_VERSION, KRaft, one node, $([ "$ROLE" = all ] && echo "on 127.0.0.1" || echo "advertising ${ADVERTISE_IP:-<auto-detected>}"), heap $KAFKA_HEAP, in $KAFKA_HOME, data $KAFKA_DATA"
elif [ "$DO_BROKER" = yes ]; then
    say "  broker      redpanda${REDPANDA_VERSION:+, pinned $REDPANDA_VERSION}, $([ "$ROLE" = all ] && echo "single node on 127.0.0.1" || echo "advertising ${ADVERTISE_IP:-<auto-detected>}${SEED_IPS:+, cluster of $SEED_IPS}")"
else
    say "  broker      skip"
fi
say "  node        $([ "$DO_NODE" = yes ] && echo "yes, $NODE_INSTALL_MAJOR" || echo skip)"
say "  java        $([ "$WITH_JAVA" = yes ] && echo "yes, Temurin 25" || echo "skip -- not needed to RUN FireFlo")"
if [ "$DRY_RUN" = yes ]; then say "  DRY RUN -- nothing will be changed"; fi
if [ "$DO_BROKER" = yes ] && [ "$BROKER" = redpanda ]; then broker_resource_check; fi

confirm "Proceed?" || die "nothing was changed."

# 'if' rather than '[ x ] && do_thing'. Under 'set -e' a false test at statement
# level is a failing command, so the AND-list form exits the script -- and
# because the last of these is the one most often switched off, the symptom is
# a run that does everything and then reports failure.
#
# Java comes straight after the base packages: --broker kafka needs it to
# format its storage and start.
do_base
if [ "$WITH_JAVA"      = yes ]; then do_java;            fi
if [ "$DO_PG"          = yes ]; then do_postgres;        fi
if [ "$DO_PG_ACCESS"   = yes ]; then do_postgres_access; fi
if [ "$DO_BROKER"      = yes ]; then
    if [ "$BROKER" = kafka ]; then do_kafka; else do_redpanda; fi
fi
if [ "$DO_NODE"        = yes ]; then do_node;            fi
if [ "$DO_GW_TOOLS"    = yes ]; then do_gateway_tools;   fi
if [ "$DO_PANEL_TOOLS" = yes ]; then do_panel_tools;     fi

summary
