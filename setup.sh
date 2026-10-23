#!/bin/sh
# Prepare an Ubuntu or Debian host for FireFlo.
#
#   sudo ./setup.sh [--role ROLE] [options]
#
#   --role ROLE        what this host is for. One of:
#                        all      everything on one box: PostgreSQL, a single
#                                 Redpanda node advertising 127.0.0.1, Node for
#                                 the control panel, the gateway's client tools.
#                                 This is the DEFAULT and what 0.13 did, with
#                                 Redpanda where RabbitMQ used to be
#                        gateway  a gateway node. Client tools only: no database
#                                 server, no broker, no Node. Pair with --db-host
#                                 and --kafka-bootstrap at install time
#                        db       the PostgreSQL server the gateway nodes share
#                        broker   a Redpanda node, alone or one of three
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
#                      a cluster of one
#   --with-java        also install Temurin JDK 25, from Adoptium. OFF by
#                      default: the shipped gateway is a native image and opens
#                      no JDK. You want this only to BUILD from source
#   --no-node          --role all only: skip Node. Node 22 is installed because
#                      the control panel needs it and Ubuntu ships 18, which
#                      Next.js will not run on
#   --no-postgres      --role all only: skip the PostgreSQL server
#   --kafka-kraft-notes  print a note on running Apache Kafka (KRaft) instead of
#                      Redpanda, and exit
#   --dry-run          print every command and touch nothing
#   --yes              do not prompt
#   --help
#
#   --no-rabbitmq      refused. RabbitMQ left FireFlo in 0.14; see below
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
#     configuration. Those are fireflo-install's, which does them carefully.
#     The one host-level edit it will make is PostgreSQL's listen address and
#     pg_hba.conf, and only when you name the subnet with --allow-from.
#   * It does not write firewall rules. It prints them, per role, because which
#     hosts may reach which port is a fact about YOUR network, and ufw on a
#     host you are ssh'd into is not something to enable from a script.
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

# The oldest PostgreSQL the schema runs on. Below this the Flyway migrations
# fail partway, which leaves a half-migrated database rather than a clean
# refusal -- so it is checked before a server is installed, not after.
PG_MIN_MAJOR=14

# Node 20 is the floor Next.js needs; 22 is what gets installed when it is
# missing. Both matter: a host that already has 20 is fine and must not be
# given a third-party apt repository it does not need.
NODE_MIN_MAJOR=20
NODE_INSTALL_MAJOR=22

# Redpanda. Empty installs whatever the repository's stable channel is today;
# set REDPANDA_VERSION in the environment to pin the deb (the full package
# version string, e.g. 25.2.1-1). Pin it when you are building the second and
# third node of a cluster: the three should match, and 'stable' moves.
REDPANDA_VERSION=${REDPANDA_VERSION:-}
REDPANDA_REPO_SETUP='https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh'

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

# ---------------------------------------------------------------------------
# the host
# ---------------------------------------------------------------------------
# Adoptium, NodeSource and Redpanda all publish per CODENAME, not per version
# number. A release none of them publishes for has no correct action available,
# and writing the sources.list entry anyway would 404 at the next 'apt update'
# -- breaking package management on the host for everything else, discovered
# weeks later by somebody who never ran this script. So an unknown codename
# refuses.
detect_host() {
    [ -r /etc/os-release ] || die "no /etc/os-release -- this is not a Debian or Ubuntu host."
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID=${ID:-unknown}
    OS_VER=${VERSION_ID:-unknown}
    OS_NAME=${VERSION_CODENAME:-}
    OS_PRETTY=${PRETTY_NAME:-$OS_ID $OS_VER}
    OS_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

    case $OS_ID in
        ubuntu|debian) ;;
        *) die "$OS_PRETTY is not supported. This script handles Ubuntu and Debian.
            Everything it does is a plain apt install -- see the header and do it by hand." ;;
    esac
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
    have apt-get || die "no apt-get. This script only handles apt-based hosts."
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
installed_pg_major() {
    for _pgbin in /usr/lib/postgresql/*/bin/postgres; do
        [ -x "$_pgbin" ] || continue
        echo "$_pgbin" | sed 's#/usr/lib/postgresql/\([0-9]*\)/.*#\1#'
    done | sort -rn | head -1
}

major_of() { echo "$1" | sed 's/^v//; s/[^0-9]*\([0-9]*\).*/\1/'; }

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
    run apt-get install -y -qq postgresql-client netcat-openbsd curl jq rsync python3
    TOOLS_RESULT="postgresql-client netcat-openbsd curl jq rsync python3"
    say "   $TOOLS_RESULT"
}

do_postgres() {
    step "PostgreSQL"
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
    _confdir="/etc/postgresql/${PG_MAJOR:-<n>}/main"
    _conf="$_confdir/postgresql.conf"
    _hba="$_confdir/pg_hba.conf"
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
        if [ "$DRY_RUN" = yes ]; then
            say "   would run: systemctl restart postgresql"
        elif have_systemd; then
            systemctl restart postgresql
            say "   PostgreSQL restarted."
        else
            say "   systemd is not running here; restart PostgreSQL yourself for the change to take."
        fi
    fi
    PG_ACCESS_RESULT="listen_addresses='*', pg_hba allows: $ALLOW_FROM"
}

# Redpanda: a Kafka-protocol broker in one binary, which is why it is the one
# this script installs. The gateway speaks the Kafka protocol and nothing
# Redpanda-specific, so an Apache Kafka cluster you already run is equally
# valid -- see --kafka-kraft-notes -- this script just does not install one.
#
# Ships as a deb for amd64 (x86_64) and arm64 (aarch64) and nothing else, so
# the architecture is checked before the repository is added.
do_redpanda() {
    step "Redpanda"
    case $OS_ARCH in
        amd64|x86_64|arm64|aarch64) ;;
        *) die "Redpanda publishes debs for amd64 and arm64 only, and this host is $OS_ARCH.
            Put the broker on another machine and point the gateway at it with --kafka-bootstrap." ;;
    esac

    if [ "$ROLE" = all ]; then
        ADVERTISE_IP=127.0.0.1
    elif [ -z "$ADVERTISE_IP" ]; then
        ADVERTISE_IP=$(detect_ip)
        [ -n "$ADVERTISE_IP" ] || die "could not work out this host's address; pass --advertise-ip."
        say "   Advertising $ADVERTISE_IP (auto-detected; override with --advertise-ip)."
    fi
    if [ -n "$SEED_IPS" ]; then
        case ",$SEED_IPS," in
            *",$ADVERTISE_IP,"*) ;;
            *) die "--ips $SEED_IPS does not include this node's own address $ADVERTISE_IP.
                The list is every node of the cluster, this one included." ;;
        esac
    fi

    if have rpk && dpkg -s redpanda >/dev/null 2>&1; then
        _have=$(rpk version 2>/dev/null | head -1 | sed 's/^[^0-9]*//')
        say "   redpanda is already installed (${_have:-version unknown}). Leaving its configuration alone."
        say "   To re-point it: rpk redpanda config bootstrap --self $ADVERTISE_IP${SEED_IPS:+ --ips $SEED_IPS}"
        BROKER_RESULT="present${_have:+, $_have}"
        return 0
    fi

    # The vendor's repository script writes the apt source and key for this
    # codename. It is fetched over TLS from the vendor's own host; the -1 asks
    # curl for TLS 1.x and -f makes a 404 a failure rather than an empty script
    # fed to a shell. Read it first if you like:
    #   curl -1sLf "$REDPANDA_REPO_SETUP" | less
    say "   Adding the Redpanda apt repository ($OS_NAME, $OS_ARCH)."
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: curl -1sLf '$REDPANDA_REPO_SETUP' | bash"
    else
        curl -1sLf "$REDPANDA_REPO_SETUP" | bash >/dev/null
    fi
    run apt-get install -y -qq "redpanda${REDPANDA_VERSION:+=$REDPANDA_VERSION}"

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
    BROKER_RESULT="installed${_ver:+, $_ver}, advertising $ADVERTISE_IP${SEED_IPS:+, seeds $SEED_IPS}"
    say "   Installed and enabled. No user, ACL or SASL was configured -- see the summary."
}

do_node() {
    step "Node"
    if have node; then
        _have=$(major_of "$(node --version 2>/dev/null)")
        if [ -n "$_have" ] && [ "$_have" -ge "$NODE_MIN_MAJOR" ] 2>/dev/null; then
            say "   Node $_have is already installed. Leaving it alone."
            NODE_RESULT="present, $_have"
            return 0
        fi
        say "   Node $_have is installed and the control panel needs $NODE_MIN_MAJOR or newer."
    fi
    say "   Adding NodeSource for Node $NODE_INSTALL_MAJOR ($OS_NAME)."
    if [ "$DRY_RUN" = yes ]; then
        say "   would run: curl -fsSL https://deb.nodesource.com/setup_$NODE_INSTALL_MAJOR.x | bash -"
    else
        curl -fsSL "https://deb.nodesource.com/setup_$NODE_INSTALL_MAJOR.x" | bash - >/dev/null
    fi
    run apt-get install -y -qq nodejs
    NODE_RESULT="installed, $NODE_INSTALL_MAJOR"
}

# The panel reads the gateway's database directly, so it wants psql for the
# same 3am reason the gateway does, and nothing else beyond Node.
do_panel_tools() {
    step "Panel client tools"
    run apt-get install -y -qq postgresql-client curl
    TOOLS_RESULT="postgresql-client curl"
    say "   $TOOLS_RESULT"
}

do_java() {
    step "Java"
    if have java; then
        _have=$(java -version 2>&1 | head -1 | sed 's/[^0-9]*\([0-9]*\).*/\1/')
        if [ -n "$_have" ] && [ "$_have" -ge 25 ] 2>/dev/null; then
            say "   Java $_have is already installed. Leaving it alone."
            JAVA_RESULT="present, $_have"
            return 0
        fi
    fi
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

# ---------------------------------------------------------------------------
# notes
# ---------------------------------------------------------------------------
kafka_kraft_notes() {
    cat <<'EOF'
Apache Kafka instead of Redpanda

The gateway speaks the Kafka wire protocol and nothing broker-specific, so a
3-broker Apache Kafka cluster in KRaft mode (no ZooKeeper) is supported. This
script does not install one: Kafka is a JVM application with its own sizing,
its own tuning and usually its own team, and an apt install that guessed at
any of that would be worse than none.

What the gateway needs from it is the same as from Redpanda:

  * the brokers' addresses, handed to fireflo-install as
      --kafka-bootstrap kafka1:9092,kafka2:9092,kafka3:9092
  * topics prefixed  fireflo.   and consumer groups prefixed  fireflo-  --
    a principal allowed to produce and consume on those prefixes if ACLs are on

The topic list, sizing and the KRaft notes are in the gateway tarball at
docs/21-clustering.md. Redpanda is what this script installs because it is one
binary speaking the same protocol; it is a recommendation, not a requirement.
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

print_ufw_from() {
    # $1 port, $2 comment, then the subnets or a placeholder
    _port=$1; _what=$2; shift 2
    for _src in "$@"; do
        echo "  sudo ufw allow from $_src to any port $_port proto tcp comment '$_what'"
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
    echo
    if [ -n "$ALLOW_FROM" ]; then
        echo "Gateway access was configured for: $ALLOW_FROM"
        echo "The files edited (originals kept beside them as *.bak.<timestamp>):"
        echo "  /etc/postgresql/${PG_MAJOR:-<n>}/main/postgresql.conf   listen_addresses = '*'"
        echo "  /etc/postgresql/${PG_MAJOR:-<n>}/main/pg_hba.conf       the lines below"
    else
        echo "Nothing was edited to let gateways in: no --allow-from was given. The gateway"
        echo "nodes are on another subnet, so the server needs these, and then a restart:"
        echo
        echo "  /etc/postgresql/${PG_MAJOR:-<n>}/main/postgresql.conf:"
        echo "  listen_addresses = '*'"
        echo
        echo "  /etc/postgresql/${PG_MAJOR:-<n>}/main/pg_hba.conf:"
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
This script does not enable ufw; these are the rules when you do:

  sudo ufw allow OpenSSH
EOF
    # shellcheck disable=SC2086
    print_ufw_from 5432 'PostgreSQL from FireFlo gateways' ${ALLOW_FROM:-<gateway-cidr>}
    echo "  sudo ufw allow from <panel-host-ip> to any port 5432 proto tcp comment 'PostgreSQL from the control panel'"
}

summary_broker_next() {
    _bs="${ADVERTISE_IP:-<broker-ip>}:9092"
    cat <<EOF

Redpanda is listening on $_bs with no authentication and no ACLs. On a
single box with 9092 closed to the outside that is fine. On a broker host it is
not: do the firewall first, then the credentials, in this order.

Firewall. 9092 is the Kafka API (gateways), 9644 the admin API (the panel
and monitoring), 33145 the RPC port (the other brokers, and only them). This
script does not enable ufw; these are the rules when you do:

  sudo ufw allow OpenSSH
  sudo ufw allow from <gateway-cidr> to any port 9092 proto tcp comment 'Kafka API from FireFlo gateways'
  sudo ufw allow from <panel-host-ip> to any port 9644 proto tcp comment 'Redpanda admin API from the panel'
EOF
    if [ -n "$SEED_IPS" ]; then
        for _peer in $(echo "$SEED_IPS" | tr ',' ' '); do
            if [ "$_peer" = "$ADVERTISE_IP" ]; then continue; fi
            echo "  sudo ufw allow from $_peer to any port 33145 proto tcp comment 'Redpanda RPC from a peer broker'"
            echo "  sudo ufw allow from $_peer to any port 9092 proto tcp comment 'Kafka API from a peer broker'"
        done
    else
        echo "  sudo ufw allow from <peer-broker-ip> to any port 33145 proto tcp comment 'Redpanda RPC from a peer broker'   # cluster only"
    fi
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
'fireflo-install --firewall' writes the inbound SMPP and HTTP rules; the rest
when you enable ufw:

  sudo ufw allow OpenSSH
  sudo ufw allow from <customer-or-lb-cidr> to any port 2775 proto tcp comment 'SMPP'
  sudo ufw allow from <customer-or-lb-cidr> to any port 8080 proto tcp comment 'FireFlo HTTP API'
  sudo ufw allow from <panel-host-ip> to any port 9000 proto tcp comment 'FireFlo management from the panel'
EOF
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
    printf '  %-12s %s\n' "host"       "$OS_PRETTY ($OS_NAME, $OS_ARCH)"
    printf '  %-12s %s\n' "role"       "$ROLE"
    printf '  %-12s %s\n' "postgresql" "${PG_RESULT:-skipped}"
    if [ -n "${PG_ACCESS_RESULT:-}" ]; then printf '  %-12s %s\n' "pg access" "$PG_ACCESS_RESULT"; fi
    printf '  %-12s %s\n' "redpanda"   "${BROKER_RESULT:-skipped}"
    printf '  %-12s %s\n' "node"       "${NODE_RESULT:-skipped}"
    printf '  %-12s %s\n' "tools"      "${TOOLS_RESULT:-skipped}"
    printf '  %-12s %s\n' "java"       "${JAVA_RESULT:-not installed -- the gateway is native and needs none}"

    case $ROLE in
        all)
            if [ "$WITH_POSTGRES" = yes ]; then summary_db_commands; fi
            if [ -n "${BROKER_RESULT:-}" ]; then
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
        --with-java)   WITH_JAVA=yes; shift ;;
        --no-node)     WITH_NODE=no; NO_NODE_GIVEN=yes; shift ;;
        --no-postgres) WITH_POSTGRES=no; NO_PG_GIVEN=yes; shift ;;
        # Recognised so that a 0.13 runbook fails on its first line with the
        # reason, rather than on 'unknown option' with none.
        --no-rabbitmq) die "RabbitMQ is no longer part of FireFlo (removed in 0.14). This script now installs Redpanda for --role broker|all; see README 'Multi-host and clustering'." ;;
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

say "FireFlo host setup"
say "  host        $OS_PRETTY ($OS_NAME, $OS_ARCH)"
say "  role        $ROLE"
say "  postgresql  $([ "$DO_PG" = yes ] && echo "yes, $PG_MIN_MAJOR+" || echo skip)"
if [ "$DO_PG_ACCESS" = yes ]; then
    say "  pg access   $([ -n "$ALLOW_FROM" ] && echo "open to $ALLOW_FROM (edits postgresql.conf and pg_hba.conf, with backups)" || echo "print the lines only -- no --allow-from")"
fi
if [ "$DO_BROKER" = yes ]; then
    say "  redpanda    yes${REDPANDA_VERSION:+, pinned $REDPANDA_VERSION}, $([ "$ROLE" = all ] && echo "single node on 127.0.0.1" || echo "advertising ${ADVERTISE_IP:-<auto-detected>}${SEED_IPS:+, cluster of $SEED_IPS}")"
else
    say "  redpanda    skip"
fi
say "  node        $([ "$DO_NODE" = yes ] && echo "yes, $NODE_INSTALL_MAJOR" || echo skip)"
say "  java        $([ "$WITH_JAVA" = yes ] && echo "yes, Temurin 25" || echo "skip -- not needed to RUN FireFlo")"
if [ "$DRY_RUN" = yes ]; then say "  DRY RUN -- nothing will be changed"; fi

confirm "Proceed?" || die "nothing was changed."

# 'if' rather than '[ x ] && do_thing'. Under 'set -e' a false test at statement
# level is a failing command, so the AND-list form exits the script -- and
# because the last of these is the one most often switched off, the symptom is
# a run that does everything and then reports failure.
do_base
if [ "$DO_PG"          = yes ]; then do_postgres;        fi
if [ "$DO_PG_ACCESS"   = yes ]; then do_postgres_access; fi
if [ "$DO_BROKER"      = yes ]; then do_redpanda;        fi
if [ "$DO_NODE"        = yes ]; then do_node;            fi
if [ "$DO_GW_TOOLS"    = yes ]; then do_gateway_tools;   fi
if [ "$DO_PANEL_TOOLS" = yes ]; then do_panel_tools;     fi
if [ "$WITH_JAVA"      = yes ]; then do_java;            fi

summary
