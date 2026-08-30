#!/bin/sh
# Remove a FireFlo install from this host.
#
#   sudo ./cleanup.sh --list
#   sudo ./cleanup.sh --tenant NAME [options]
#   sudo ./cleanup.sh --service UNIT [options]
#
#   --list             show every FireFlo install found, and stop
#   --tenant NAME      remove the install whose units are fireflo-NAME and
#                      fireflo-NAME-panel
#   --service UNIT     remove one install by its exact systemd unit name, for
#                      installs whose service name was set with --service-name
#                      and does not follow from a tenant
#   --gateway-only     leave the panel alone
#   --panel-only       leave the gateway alone
#   --purge-data       ALSO delete the data directory. Off by default -- see below
#   --purge-logs       also delete the log directory
#   --remove-user      also delete the service account, if nothing else uses it
#   --dry-run          print every command and touch nothing
#   --yes              do not prompt
#   --help
#
# WHAT THIS REMOVES
#
#   The systemd units (service, and the -logclean service and timer beside it),
#   the application directory, and the configuration directory. That is the
#   install. Everything below is deliberately left alone.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * It does not touch PostgreSQL, RabbitMQ, Node or Java. setup.sh installs
#     those HOST-WIDE, not per tenant, and on a host running two tenants -- or
#     anything else at all -- removing them to clean up one install would take
#     the others down with it. Uninstall them yourself if this host is being
#     retired: `apt purge postgresql rabbitmq-server nodejs`.
#   * It does not drop a database, a role or a broker user. Those hold CDRs,
#     balances, customer configuration and statements, and they outlive the
#     software that reads them -- an install is replaceable and the data is not.
#     The summary prints the psql commands if you want them gone.
#   * It does not delete the data directory unless you pass --purge-data. That
#     directory holds the DLR correlation store and, on a file-sink install,
#     every CDR the gateway has written. Deleting it is not recoverable and it
#     is not what "uninstall" means to most people.
#   * It does not delete the licence. Releasing a licence is done in your
#     account on the licence server, and doing it here would silently spend a
#     rebind on a machine that is going away. Release it there FIRST, then run
#     this -- the other order leaves the licence bound to a host that no longer
#     exists.
#   * It never removes a path it was not told about by a systemd unit on this
#     host. Nothing here is derived from a naming convention, because an install
#     that was relocated keeps its old unit and its real paths in that unit.
#
# EXIT
#
#   0  removed, or nothing to remove
#   1  refused: something is wrong and nothing was changed
#   2  usage

set -eu

LIST=no
TENANT=""
SERVICE=""
DO_GATEWAY=yes
DO_PANEL=yes
PURGE_DATA=no
PURGE_LOGS=no
REMOVE_USER=no
DRY_RUN=no
ASSUME_YES=no

SYSTEMD_DIR=${FIREFLO_SYSTEMD_DIR:-/etc/systemd/system}

say()  { echo "$@"; }
step() { echo; echo "== $1"; }
die()  { echo "cleanup.sh: $1" >&2; exit 1; }
usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

# Every command that changes the host goes through this, so --dry-run is total
# rather than sprinkled -- and, as in setup.sh, the dry run is how this file is
# tested, because there is no container in CI to test it in.
run() {
    if [ "$DRY_RUN" = yes ]; then
        echo "   would run: $*"
        return 0
    fi
    "$@"
}

# Unlike setup.sh's confirm, a non-tty here REFUSES rather than assuming yes.
# That inversion is deliberate: for an installer "no human present" reasonably
# means "get on with it", and for a script that deletes directories it means
# nobody is watching. `--yes` is how you say it on purpose.
confirm() {
    [ "$ASSUME_YES" = yes ] && return 0
    [ -t 0 ] || die "not running interactively, and --yes was not given. Nothing was changed."
    printf '%s [y/N] ' "$1"
    read -r _a || return 1
    case ${_a:-n} in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Refuse to delete anything that does not look like a directory an install owns.
#
# The failure this exists for is a malformed or truncated unit file yielding an
# empty WorkingDirectory, after which `rm -rf $DIR` is `rm -rf /`. So: absolute,
# more than one component deep, and never one of the shared parents an install
# lives INSIDE rather than IS.
safe_to_remove() {
    _p=$1
    case $_p in
        "" | [!/]* | *"/.."* | *"/./"*) return 1 ;;
    esac
    while :; do case $_p in */) _p=${_p%/} ;; *) break ;; esac; done
    [ -n "$_p" ] || return 1

    # An explicit list of directories an install lives INSIDE rather than IS.
    # A depth rule was tried first and is not enough: /var/lib and /var/log are
    # two components deep and look exactly like /opt/fireflo to a counter, so a
    # unit whose ReadWritePaths said "/var/lib /var/log" -- which is what a
    # half-written or hand-edited unit says -- would have had both deleted.
    # Caught by the malformed-unit test, which is why that test exists.
    for _deny in / /bin /boot /dev /etc /home /lib /lib32 /lib64 /libx32 \
                 /media /mnt /opt /proc /root /run /sbin /srv /sys /tmp /usr /var \
                 /etc/systemd /etc/systemd/system /run/systemd \
                 /usr/bin /usr/lib /usr/local /usr/sbin /usr/share /usr/src \
                 /var/cache /var/lib /var/log /var/opt /var/run /var/spool /var/tmp
    do
        [ "$_p" = "$_deny" ] && return 1
    done
    return 0
}

remove_dir() {
    _what=$1 _dir=$2
    [ -n "$_dir" ] || return 0
    if ! safe_to_remove "$_dir"; then
        say "   REFUSED to remove $_what at '$_dir' -- that is not a path this script will delete."
        return 0
    fi
    if [ ! -e "$_dir" ]; then
        say "   $_what already gone ($_dir)"
        return 0
    fi
    run rm -rf -- "$_dir"
    say "   removed $_what  $_dir"
}

unit_value() {  # unit_value <file> <Directive>
    [ -f "$1" ] || return 0
    sed -n "s/^$2=//p" "$1" | tail -1
}

# Every FireFlo main unit on this host. -logclean units are companions and are
# handled with their parent, never discovered as installs of their own.
find_units() {
    for _u in "$SYSTEMD_DIR"/fireflo*.service; do
        [ -e "$_u" ] || continue
        case $(basename "$_u") in *-logclean.service) continue ;; esac
        echo "$_u"
    done
}

kind_of() {
    case $(unit_value "$1" Description) in
        *"Control Panel"*) echo panel ;;
        *) echo gateway ;;
    esac
}

describe() {  # describe <unitfile>
    _u=$1
    _name=$(basename "$_u" .service)
    _kind=$(kind_of "$_u")
    _app=$(unit_value "$_u" WorkingDirectory)
    _envf=$(unit_value "$_u" EnvironmentFile)
    _conf=""; [ -z "$_envf" ] || _conf=$(dirname "$_envf")
    _user=$(unit_value "$_u" User)
    _rw=$(unit_value "$_u" ReadWritePaths)
    _state=$(systemctl is-active "$_name" 2>/dev/null || true)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$_name" "$_kind" "${_state:-unknown}" "$_app" "$_conf" "$_user" "$_rw"
}

do_list() {
    _any=no
    printf '%-26s %-8s %-9s %s\n' UNIT KIND STATE "APPLICATION DIRECTORY"
    for _u in $(find_units); do
        _any=yes
        describe "$_u" | while IFS='	' read -r n k s a c usr rw; do
            printf '%-26s %-8s %-9s %s\n' "$n" "$k" "$s" "${a:-?}"
            [ -z "$c" ]  || printf '%-26s   config %s\n' "" "$c"
            [ -z "$rw" ] || printf '%-26s   writes %s\n' "" "$rw"
        done
    done
    [ "$_any" = yes ] || say "No FireFlo install found on this host."
}

remove_one() {
    _u=$1
    _name=$(basename "$_u" .service)
    _kind=$(kind_of "$_u")
    _app=$(unit_value "$_u" WorkingDirectory)
    _envf=$(unit_value "$_u" EnvironmentFile)
    _conf=""; [ -z "$_envf" ] || _conf=$(dirname "$_envf")
    _user=$(unit_value "$_u" User)
    _rw=$(unit_value "$_u" ReadWritePaths)

    step "Removing $_name ($_kind)"

    # stop first, so nothing is writing into a directory being deleted
    run systemctl stop "$_name" 2>/dev/null || true
    run systemctl disable "$_name" 2>/dev/null || true
    for _c in "$_name-logclean.timer" "$_name-logclean.service"; do
        [ -e "$SYSTEMD_DIR/$_c" ] || continue
        run systemctl stop "$_c" 2>/dev/null || true
        run systemctl disable "$_c" 2>/dev/null || true
        run rm -f -- "$SYSTEMD_DIR/$_c"
        say "   removed companion unit $_c"
    done
    run rm -f -- "$_u"
    say "   removed unit $(basename "$_u")"
    run systemctl daemon-reload

    remove_dir "application" "$_app"
    remove_dir "configuration" "$_conf"

    # ReadWritePaths is "DATA LOG" for a gateway, in that order, and is the only
    # place the unit records either. Purging is opt-in per the header.
    _data=""; _logs=""
    if [ -n "$_rw" ]; then
        # shellcheck disable=SC2086
        set -- $_rw
        _data=${1:-}; _logs=${2:-}
    fi
    if [ "$PURGE_DATA" = yes ]; then
        remove_dir "data" "$_data"
    elif [ -n "$_data" ]; then
        say "   KEPT data          $_data   (--purge-data to remove)"
    fi
    if [ "$PURGE_LOGS" = yes ]; then
        remove_dir "logs" "$_logs"
    elif [ -n "$_logs" ]; then
        say "   KEPT logs          $_logs   (--purge-logs to remove)"
    fi

    if [ "$REMOVE_USER" = yes ] && [ -n "$_user" ] && [ "$_user" != root ]; then
        # only if no surviving FireFlo unit still runs as this account -- two
        # tenants commonly share one service user, and removing it under the
        # second one is how the remaining gateway fails to restart at 3am
        _still=no
        for _o in $(find_units); do
            [ "$_o" = "$_u" ] && continue
            [ "$(unit_value "$_o" User)" = "$_user" ] && _still=yes
        done
        if [ "$_still" = yes ]; then
            say "   KEPT user '$_user' -- another FireFlo unit still runs as it"
        else
            run userdel "$_user" 2>/dev/null || say "   could not remove user '$_user' (in use, or not present)"
        fi
    fi
}

while [ $# -gt 0 ]; do
    case $1 in
        --list)        LIST=yes; shift ;;
        --tenant)      TENANT=${2:-}; [ -n "$TENANT" ] || die "--tenant needs a name."; shift 2 ;;
        --service)     SERVICE=${2:-}; [ -n "$SERVICE" ] || die "--service needs a unit name."; shift 2 ;;
        --gateway-only) DO_PANEL=no; shift ;;
        --panel-only)  DO_GATEWAY=no; shift ;;
        --purge-data)  PURGE_DATA=yes; shift ;;
        --purge-logs)  PURGE_LOGS=yes; shift ;;
        --remove-user) REMOVE_USER=yes; shift ;;
        --dry-run)     DRY_RUN=yes; shift ;;
        --yes)         ASSUME_YES=yes; shift ;;
        -h|--help|help) usage; exit 0 ;;
        *) echo "cleanup.sh: unknown option '$1'." >&2
           echo "Flags take space-separated values: --tenant acme, not --tenant=acme." >&2
           exit 2 ;;
    esac
done

if [ "$LIST" = yes ]; then
    do_list
    exit 0
fi

[ "$DO_GATEWAY" = yes ] || [ "$DO_PANEL" = yes ] ||
    die "--gateway-only and --panel-only together leave nothing to do."

TARGETS=""
for u in $(find_units); do
    name=$(basename "$u" .service)
    kind=$(kind_of "$u")
    [ "$kind" = gateway ] && [ "$DO_GATEWAY" = no ] && continue
    [ "$kind" = panel ]   && [ "$DO_PANEL"   = no ] && continue
    if [ -n "$SERVICE" ]; then
        [ "$name" = "$SERVICE" ] || [ "$name" = "${SERVICE%.service}" ] || continue
    elif [ -n "$TENANT" ]; then
        case $name in
            fireflo-"$TENANT"|fireflo-"$TENANT"-panel) ;;
            *) continue ;;
        esac
    fi
    TARGETS="$TARGETS $u"
done

if [ -z "${TARGETS# }" ]; then
    if [ -n "$TENANT" ]; then
        die "no install called '$TENANT' was found on this host. Run --list to see what is here."
    elif [ -n "$SERVICE" ]; then
        die "no unit called '$SERVICE' was found in $SYSTEMD_DIR."
    fi
    say "No FireFlo install found on this host. Nothing to do."
    exit 0
fi

# Refuse to guess. Without a target, removing every install on a host that has
# more than one is never what somebody meant to type.
if [ -z "$TENANT" ] && [ -z "$SERVICE" ]; then
    count=0
    for t in $TARGETS; do count=$((count + 1)); done
    if [ "$count" -gt 1 ]; then
        say "This host has $count FireFlo installs:"
        say ""
        do_list
        say ""
        die "name one with --tenant or --service. Refusing to remove them all on a guess."
    fi
fi

step "About to remove"
for t in $TARGETS; do
    describe "$t" | while IFS='	' read -r n k s a c usr rw; do
        say "  $n ($k, currently $s)"
        [ -z "$a" ] || say "      application  $a"
        [ -z "$c" ] || say "      config       $c"
    done
done
say ""
[ "$PURGE_DATA" = yes ] && say "  --purge-data: THE DATA DIRECTORY WILL BE DELETED. This is not recoverable."
[ "$PURGE_LOGS" = yes ] && say "  --purge-logs: the log directory will be deleted."
say "  Databases, roles, PostgreSQL, RabbitMQ and Node are NOT touched."
say ""

confirm "Remove the above?" || die "nothing was changed."

for t in $TARGETS; do
    remove_one "$t"
done

step "Done"
say "Removed. Not touched, and yours to deal with if this host is being retired:"
say ""
say "  the database and its role   psql -c 'DROP DATABASE <name>' -c 'DROP ROLE <user>'"
say "  the host services           apt purge postgresql rabbitmq-server nodejs"
say "  the licence                 release it in your account on the licence server"
say ""
say "Release the licence there if you have not already: a licence still bound to"
say "a host that no longer exists has to wait out the tolerance window before the"
say "next machine can take it."
[ "$DRY_RUN" = yes ] && say "" && say "(--dry-run: nothing above actually happened.)"
exit 0
