#!/bin/sh
# Prepare an Ubuntu or Debian host for FireFlo.
#
#   sudo ./setup.sh [options]
#
#   --with-java        also install Temurin JDK 25, from Adoptium. OFF by
#                      default: the shipped gateway is a native image and opens
#                      no JDK. You want this only to BUILD from source
#   --no-node          skip Node. Node 22 is installed by default because the
#                      control panel needs it and Ubuntu ships 18, which
#                      Next.js will not run on. Skip it on a gateway-only host
#   --no-postgres      skip PostgreSQL
#   --no-rabbitmq      skip RabbitMQ
#   --dry-run          print every command and touch nothing
#   --yes              do not prompt
#   --help
#
# WHAT THIS IS FOR
#
# 'fireflo-install' installs the gateway. It does NOT install the services the
# gateway talks to: its package step adds postgresql-CLIENT and no server, and
# it never mentions a broker. So between unpacking the tarball and running the
# installer there is a step nobody wrote down. This is that step.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * It does not create a database, a role or a password. Installing a package
#     is impersonal and reversible; creating a role and writing its password to
#     a file is neither, and it is not a decision a setup script should make on
#     your behalf. You create them, and pass them to fireflo-install. The
#     summary at the end prints the commands.
#   * It does not create a RabbitMQ user or vhost, for the same reason. The
#     package's default 'guest' account is already restricted to loopback by the
#     broker itself, which is the correct default and the only one that needs no
#     secret.
#   * It does not download, verify or install FireFlo, and it never asks for a
#     licence key. Keeping those separate is what lets this file be read in full
#     before it is run -- which you should do, because you are about to run it
#     as root.
#   * It does not create a service user, a systemd unit, a firewall rule or any
#     configuration. Those are fireflo-install's, which does them carefully.
#
# This file is not signed. Neither are the release tarballs. Read it.

set -eu

WITH_JAVA=no
WITH_NODE=yes
WITH_POSTGRES=yes
WITH_RABBITMQ=yes
DRY_RUN=no
ASSUME_YES=no

# The oldest PostgreSQL the schema runs on. Below this the Flyway migrations
# fail partway, which leaves a half-migrated database rather than a clean
# refusal -- so it is checked before a server is installed, not after.
PG_MIN_MAJOR=14

# Node 20 is the floor Next.js needs; 22 is what gets installed when it is
# missing. Both matter: a host that already has 20 is fine and must not be
# given a third-party apt repository it does not need.
NODE_MIN_MAJOR=20
NODE_INSTALL_MAJOR=22

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

confirm() {
    [ "$ASSUME_YES" = yes ] && return 0
    [ -t 0 ] || return 0          # a pipe is not a person; --yes is implied
    printf '%s [Y/n] ' "$1"
    read -r _a || return 1
    case ${_a:-y} in [Nn]*) return 1 ;; *) return 0 ;; esac
}

# ---------------------------------------------------------------------------
# the host
# ---------------------------------------------------------------------------
# Adoptium and NodeSource both publish per CODENAME, not per version number. A
# release neither of them publishes for has no correct action available, and
# writing the sources.list entry anyway would 404 at the next 'apt update' --
# breaking package management on the host for everything else, discovered weeks
# later by somebody who never ran this script. So an unknown codename refuses.
detect_host() {
    [ -r /etc/os-release ] || die "no /etc/os-release -- this is not a Debian or Ubuntu host."
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID=${ID:-unknown}
    OS_VER=${VERSION_ID:-unknown}
    OS_NAME=${VERSION_CODENAME:-}
    OS_PRETTY=${PRETTY_NAME:-$OS_ID $OS_VER}

    case $OS_ID in
        ubuntu|debian) ;;
        *) die "$OS_PRETTY is not supported. This script handles Ubuntu and Debian.
            Everything it does is a plain apt install -- see the header and do it by hand." ;;
    esac
    [ -n "$OS_NAME" ] || die "/etc/os-release has no VERSION_CODENAME, and the Adoptium and
            NodeSource repositories are addressed by codename. Cannot continue safely."

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
            It will not guess: NodeSource and Adoptium publish per codename, and an apt source
            written for a suite they do not publish breaks package management on this host for
            everything, not just FireFlo.
            Known: ubuntu focal jammy noble plucky; debian bullseye bookworm trixie.
            Install postgresql (14+), rabbitmq-server and nodejs (20+) by hand, then run
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

do_postgres() {
    step "PostgreSQL"
    _have=$(installed_pg_major)
    if [ -n "$_have" ]; then
        if [ "$_have" -ge "$PG_MIN_MAJOR" ] 2>/dev/null; then
            say "   PostgreSQL $_have is already installed. Leaving it alone."
            PG_RESULT="present, $_have"
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
    run systemctl enable --now postgresql
    PG_RESULT="installed${_distro:+, $_distro}"
    say "   Installed and enabled. No database, role or password was created -- see the summary."
}

do_rabbitmq() {
    step "RabbitMQ"
    if have rabbitmqctl || dpkg -s rabbitmq-server >/dev/null 2>&1; then
        say "   rabbitmq-server is already installed. Leaving it alone."
        MQ_RESULT="present"
        return 0
    fi
    # the distribution package, not the Team RabbitMQ repository: every release
    # this script supports ships a 3.10 or newer broker, which speaks the AMQP
    # 0-9-1 the gateway uses. A second apt repository and an Erlang pin would
    # buy a version number nothing here needs.
    run apt-get install -y -qq rabbitmq-server
    run systemctl enable --now rabbitmq-server
    MQ_RESULT="installed"
    say "   Installed and enabled. No user or vhost was created: the default 'guest'"
    say "   account is restricted to loopback by the broker itself, and creating"
    say "   credentials would mean this script inventing and storing a password."
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
summary() {
    step "Done"
    printf '  %-12s %s\n' "host"       "$OS_PRETTY ($OS_NAME)"
    printf '  %-12s %s\n' "postgresql" "${PG_RESULT:-skipped}"
    printf '  %-12s %s\n' "rabbitmq"   "${MQ_RESULT:-skipped}"
    printf '  %-12s %s\n' "node"       "${NODE_RESULT:-skipped}"
    printf '  %-12s %s\n' "java"       "${JAVA_RESULT:-not installed -- the gateway is native and needs none}"

    if [ "$WITH_POSTGRES" = yes ]; then
        cat <<'EOF'

This script created no database. FireFlo needs one, and it is yours to make:

  sudo -u postgres createuser --pwprompt fireflo
  sudo -u postgres createdb --owner=fireflo fireflo

Keep that password out of your shell history -- put it in a file and hand
fireflo-install the file, not the value:

  sudo ./scripts/fireflo-install install --from ./gateway \
      --config-source db --bootstrap \
      --db-name fireflo --db-user fireflo --db-password-file /root/fireflo-db.pw
EOF
    fi

    if [ "${MQ_RESULT:-}" != "" ]; then
        cat <<'EOF'

RabbitMQ is running with its default loopback-only 'guest' account. To use it,
add to the install command:

  --broker-uri amqp://guest:guest@127.0.0.1:5672/%2F

Without a broker the queue is in memory and a restart drops whatever has not
reached a vendor. That is the gateway's default and it is a real trade, not an
oversight.
EOF
    fi

    cat <<'EOF'

Then check the host before installing anything:

  ./scripts/fireflo-install check

Full documentation: https://docs.fireflo.au
EOF
}

# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case $1 in
        --with-java)  WITH_JAVA=yes; shift ;;
        --no-node)    WITH_NODE=no; shift ;;
        --no-postgres) WITH_POSTGRES=no; shift ;;
        --no-rabbitmq) WITH_RABBITMQ=no; shift ;;
        --dry-run)    DRY_RUN=yes; shift ;;
        --yes|-y)     ASSUME_YES=yes; shift ;;
        --help|-h)    usage 0 ;;
        *) echo "setup.sh: unknown option '$1'" >&2; usage 1 ;;
    esac
done

detect_host

[ "$DRY_RUN" = yes ] || [ "$(id -u)" = 0 ] ||
    die "run this as root: sudo ./setup.sh   (or --dry-run to see what it would do)"

say "FireFlo host setup"
say "  host        $OS_PRETTY ($OS_NAME)"
say "  postgresql  $([ "$WITH_POSTGRES" = yes ] && echo "yes, $PG_MIN_MAJOR+" || echo skip)"
say "  rabbitmq    $([ "$WITH_RABBITMQ" = yes ] && echo yes || echo skip)"
say "  node        $([ "$WITH_NODE" = yes ] && echo "yes, $NODE_INSTALL_MAJOR" || echo skip)"
say "  java        $([ "$WITH_JAVA" = yes ] && echo "yes, Temurin 25" || echo "skip -- not needed to RUN FireFlo")"
if [ "$DRY_RUN" = yes ]; then say "  DRY RUN -- nothing will be changed"; fi

confirm "Proceed?" || die "nothing was changed."

# 'if' rather than '[ x ] && do_thing'. Under 'set -e' a false test at statement
# level is a failing command, so the AND-list form exits the script -- and
# because the last of these is the one most often switched off, the symptom is
# a run that does everything and then reports failure.
do_base
if [ "$WITH_POSTGRES" = yes ]; then do_postgres; fi
if [ "$WITH_RABBITMQ" = yes ]; then do_rabbitmq; fi
if [ "$WITH_NODE"     = yes ]; then do_node;     fi
if [ "$WITH_JAVA"     = yes ]; then do_java;     fi

summary
