#!/bin/bash
# Migrate a CryoSPARC v4 database into this v5 instance.
#
# Runs inside the container, as the session user, before CryoSPARC starts.
#
# Design notes:
#   * v5's supported upgrade path is "cryosparcm update", which rewrites
#     /app/cryosparc_master. That directory lives inside a read-only Apptainer
#     image, so it cannot be used here. Instead we use the DB-only upgrade that
#     Structura described for containerised sites in
#     https://discuss.cryosparc.com/t/upgrade-v4-to-v5/24679
#     ("cryosparcm start database/cache; cryosparcm upgrade -y").
#   * The v4 database is COPIED into this instance's datadir and the copy is
#     upgraded. The untouched v4 directory is therefore the rollback path:
#     relaunching the v4 image against it must keep working.
#
# Inputs (environment):
#   CRYOSPARC_DATADIR       v5 datadir; holds config.sh, run/, cryosparc_database/
#   CRYOSPARC_MIGRATE_FROM  v4 datadir to seed from. Empty => fresh v5 instance.
#   CRYOSPARC_MIGRATE_FORCE Set to 1 to proceed despite a non-empty mongod.lock.
#
# Exit status: 0 = safe to start CryoSPARC, non-zero = do not start.

set -o pipefail

V5_DATADIR="${CRYOSPARC_DATADIR}"
V5_DBPATH="${V5_DATADIR}/cryosparc_database"
V4_DATADIR="${CRYOSPARC_MIGRATE_FROM}"
V4_DBPATH="${V4_DATADIR}/cryosparc_database"

STATE_FILE="${V5_DATADIR}/.cryosparc_v5_migration"
LOG_DIR="${V5_DATADIR}/run"
LOG_FILE="${LOG_DIR}/v5_migration_$(date +%Y%m%d_%H%M%S).log"
# xfce displays $XDG_DESKTOP_DIR, which Open OnDemand sets to $LSCRATCH/Desktop
# rather than $HOME/Desktop. cryosparc.sh resolves and exports the real location;
# fall back for standalone/admin runs of this script.
DESKTOP_DIR=${CRYOSPARC_DESKTOP_DIR:-${LSCRATCH:+${LSCRATCH}/Desktop}}
NOTICE="${DESKTOP_DIR:-${HOME}/Desktop}/CRYOSPARC-MIGRATION.txt"

mkdir -p "${LOG_DIR}"

log() { echo "$(date +'%Y-%m-%d %H:%M:%S') [migrate] $*" | tee -a "${LOG_FILE}"; }

# Leave a breadcrumb on the desktop so a user staring at an empty session knows
# what is happening; the desktop is the only UI they have during migration. Fall
# back to the data directory when there is no usable Desktop (non-desktop runs,
# or HOME pointing somewhere unwritable).
notify() {
    if mkdir -p "$(dirname "${NOTICE}")" 2>/dev/null \
       && printf '%s\n' "$*" > "${NOTICE}" 2>/dev/null; then
        return
    fi
    printf '%s\n' "$*" > "${V5_DATADIR}/CRYOSPARC-MIGRATION.txt" 2>/dev/null || true
}

set_state() { echo "$1" > "${STATE_FILE}"; }
get_state() { [ -f "${STATE_FILE}" ] && cat "${STATE_FILE}" || echo "none"; }

fail() {
    log "MIGRATION FAILED: $*"
    set_state "failed"
    notify "CryoSPARC v5 database migration FAILED

$*

Your original v4 database was not modified and is still at:
  ${V4_DBPATH}

You can keep working by starting a CryoSPARC v4.7 session.
Please send this log to the cryo-EM support team:
  ${LOG_FILE}"
    return 1
}

# Size of $1 in MB (0 if absent).
dir_size_mb() { [ -d "$1" ] && du -sm "$1" 2>/dev/null | cut -f1 || echo 0; }
# Free space in MB on the filesystem holding $1.
free_space_mb() { df -Pm "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }

###
# 1. Decide whether there is anything to do
###
case "$(get_state)" in
    done)
        log "Database already migrated to v5; nothing to do."
        rm -f "${NOTICE}"
        exit 0
        ;;
    failed)
        log "A previous migration attempt failed; refusing to start CryoSPARC."
        log "Inspect ${V5_DATADIR} and remove ${STATE_FILE} to retry."
        exit 1
        ;;
esac

# Resolve a path for comparison. readlink -f handles a path that does not exist
# yet, which the v5 directory may not on a first launch.
canonical() { readlink -f "$1" 2>/dev/null || printf '%s' "$1"; }

# Guard: the two directories must not be the same one. The whole safety model is
# that the v4 database is copied and left untouched, so that a v4 session stays
# possible; migrating a directory onto itself would destroy that and could
# corrupt the database outright.
if [ -n "${V4_DATADIR}" ] && [ "$(canonical "${V5_DATADIR}")" = "$(canonical "${V4_DATADIR}")" ]; then
    fail "'CryoSPARC Datadir' and 'Migrate database from' are the same directory:
  ${V5_DATADIR}

They must be different. 'CryoSPARC Datadir' needs to be a NEW directory for the
v5 instance; 'Migrate database from' is your existing v4 directory, which is only
ever read. Nothing has been changed."
    exit 1
fi

# Guard: the v5 directory already holds a database that this script never
# created. Most likely the user pointed 'CryoSPARC Datadir' at their existing v4
# directory. We cannot tell a v4 database from a v5 one without starting it, and
# running v5 against un-upgraded v4 data risks corrupting it -- which is exactly
# what the CryoSPARC guide warns against -- so refuse rather than guess.
if [ -d "${V5_DBPATH}" ] && [ -n "$(ls -A "${V5_DBPATH}" 2>/dev/null)" ]; then
    fail "'CryoSPARC Datadir' already contains a CryoSPARC database that was not
created by this v5 setup:
  ${V5_DBPATH}

If that is your existing CryoSPARC v4 directory, this is not where it goes:
  * put a NEW, empty directory in 'CryoSPARC Datadir'
  * put this path in 'Migrate database from'
and your v4 database will be copied there and upgraded, leaving the original
untouched.

Nothing has been changed."
    exit 1
fi

# Guard: a migration source was given but does not look like a CryoSPARC data
# directory. Starting an empty instance here would look like the migration had
# silently lost the user's projects, so treat a typo as an error.
if [ -n "${V4_DATADIR}" ] && { [ ! -d "${V4_DBPATH}" ] || [ -z "$(ls -A "${V4_DBPATH}" 2>/dev/null)" ]; }; then
    fail "'Migrate database from' does not contain a CryoSPARC database:
  ${V4_DATADIR}

Expected to find a non-empty '${V4_DBPATH##*/}' directory inside it. Check the
path - it should be the directory that holds cryosparc_database, not the
database directory itself, and not a project directory.

To start a brand new, empty CryoSPARC v5 instance instead, clear the
'Migrate database from' field. Nothing has been changed."
    exit 1
fi

if [ -z "${V4_DATADIR}" ]; then
    log "No migration source given; starting a fresh v5 instance."
    set_state "done"
    exit 0
fi

###
# 2. Pre-flight checks
###
log "Preparing to migrate CryoSPARC v4 database to v5."
log "  source (v4, read-only): ${V4_DBPATH}"
log "  target (v5):            ${V5_DBPATH}"
notify "CryoSPARC is upgrading your database to v5.

This runs once and can take anywhere from a few minutes to over an hour,
depending on how many projects and jobs you have. Please do not close this
session until CryoSPARC opens.

Progress log: ${LOG_FILE}"

# Copying a WiredTiger directory while mongod is actively writing to it yields a
# torn copy. mongod.lock holds a PID while the database is running and is
# truncated on a clean shutdown -- but a non-empty lock does NOT reliably mean
# "in use" here: Open OnDemand sessions normally end by Slurm timeout or by the
# idle culler's `pkill -9`, so mongod never gets a clean stop and a stale lock is
# the usual state. Refusing on that alone would block almost every migration.
#
# So: abort only if a mongod is demonstrably running against this directory, and
# otherwise proceed, letting WiredTiger replay its journal on the copy. The
# original is never written to, so the worst case of a torn copy is a failed
# migration the user can retry -- not data loss. Because that case exists at all,
# a stale lock escalates the post-upgrade `database check` from a warning to a
# hard failure (see below).
LOCK_WAS_STALE=0

# Match on argv[0] actually being mongod, not merely on the string "mongod"
# appearing somewhere in the command line -- otherwise any process that mentions
# both mongod and the database path (a shell running this very script, a log
# tail, an editor) is a false positive, and a false positive here aborts the
# migration for no reason.
mongod_running_on() {
    local dbpath="$1" proc args exe
    for proc in /proc/[0-9]*; do
        [ -r "${proc}/cmdline" ] || continue
        args=$(tr '\0' ' ' < "${proc}/cmdline" 2>/dev/null) || continue
        exe=${args%% *}
        [ "${exe##*/}" = "mongod" ] || continue
        if printf '%s' "${args}" | grep -qF -- "${dbpath}"; then
            return 0
        fi
    done
    return 1
}

if mongod_running_on "${V4_DBPATH}"; then
    fail "A MongoDB process is currently running against your v4 database:
  ${V4_DBPATH}

Copying it now would produce a corrupt database. Please make sure every other
CryoSPARC session of yours has fully exited, then start a new v5 session."
    exit 1
fi

if [ -s "${V4_DBPATH}/mongod.lock" ]; then
    LOCK_WAS_STALE=1
    log "NOTE: ${V4_DBPATH}/mongod.lock is not empty, so the v4 instance was not"
    log "      shut down cleanly (normal when a session is ended by Slurm or the"
    log "      idle culler). No mongod is running against it, so continuing;"
    log "      WiredTiger will replay its journal on the copy."
fi

DB_SIZE_MB=$(dir_size_mb "${V4_DBPATH}")
FREE_MB=$(free_space_mb "${V5_DATADIR}")
# The copy itself, plus room for MongoDB to rewrite collections and indexes
# during the upgrade. Half the database again, with a 2 GB floor.
HEADROOM_MB=$(( DB_SIZE_MB / 2 )); [ "${HEADROOM_MB}" -lt 2048 ] && HEADROOM_MB=2048
REQUIRED_MB=$(( DB_SIZE_MB + HEADROOM_MB ))
log "v4 database size: ${DB_SIZE_MB} MB; free space at target: ${FREE_MB} MB; required: ${REQUIRED_MB} MB"

if [ "${FREE_MB:-0}" -lt "${REQUIRED_MB}" ]; then
    fail "Not enough free space to migrate safely.

  database size : ${DB_SIZE_MB} MB
  required      : ${REQUIRED_MB} MB (copy + upgrade working space)
  available     : ${FREE_MB} MB at ${V5_DATADIR}

Free up space or point CRYOSPARC_DATADIR at a location with more room,
then start a new session. Nothing has been changed."
    exit 1
fi

###
# 3. Copy the v4 database
###
log "Copying v4 database (this may take a while)..."
mkdir -p "${V5_DBPATH}"
if ! cp -a "${V4_DBPATH}/." "${V5_DBPATH}/" >>"${LOG_FILE}" 2>&1; then
    rm -rf "${V5_DBPATH}"
    fail "Failed to copy the v4 database. See ${LOG_FILE}."
    exit 1
fi
# A stale lock from the source would stop mongod from starting on the copy.
rm -f "${V5_DBPATH}/mongod.lock"
set_state "seeded"
log "Copy complete."

###
# 4. Upgrade the copy
###
# cryosparcm initialises logging to ${CRYOSPARC_MASTER_DIR}/run/cli.log before it
# parses any argument, so an unwritable run directory makes every invocation
# fail with a PermissionError traceback. Check it up front -- otherwise the real
# cause is buried under an unrelated-looking error later.
CRYOSPARCM_RUN_DIR="${CRYOSPARC_MASTER_DIR}/run"
if ! { [ -d "${CRYOSPARCM_RUN_DIR}" ] && [ -w "${CRYOSPARCM_RUN_DIR}" ]; }; then
    fail "CryoSPARC's run directory is not writable: ${CRYOSPARCM_RUN_DIR}
      (resolves to: $(readlink -f "${CRYOSPARCM_RUN_DIR}" 2>/dev/null || echo 'unresolvable'))

Every cryosparcm command fails without it. This normally means the session did
not bind ${V5_DATADIR}/run over it correctly."
    exit 1
fi

# Distinguish "this build has no upgrade command" from "cryosparcm itself cannot
# run", which look identical if the probe's output is discarded.
if ! upgrade_probe=$(cryosparcm upgrade --help 2>&1); then
    if printf '%s' "${upgrade_probe}" | grep -qiE 'no such command|unrecognized|invalid value|usage:.*cryosparcm \[' ; then
        fail "This CryoSPARC build does not provide 'cryosparcm upgrade'.

The container-friendly database upgrade path has been removed or renamed
upstream, so this image cannot migrate a v4 database. Please report this to the
cryo-EM support team; the v5 image needs rebuilding or the migration needs to be
performed by an administrator."
    else
        fail "cryosparcm could not run, so the database was not upgraded:

${upgrade_probe}"
    fi
    exit 1
fi

# Follow the same sequence `bin/cryosparcm` uses for the database stage of its
# own update (see its install() function): a dry-run startup of the database and
# core services, then the upgrade, then a clean stop.
#
# The dry-run startup is not optional. It runs `database configure`, which
# creates the MongoDB auth users (cryosparc_admin / cryosparc_user, with
# credentials derived from the license). A v4.6.2 database has no such users, so
# going straight to `start database` + `upgrade` fails with
# "Authentication failed. / Could not find user cryosparc_admin@admin" -- which
# is the failure reported on the forum and misattributed to a license mismatch.
# A v4 database carries a MongoDB replica-set configuration pinned to the port
# it last ran on, and every migration here changes that port: v4 instances were
# allocated around 39100, and v5 refuses anything below 61000. So the replica set
# is ALWAYS stale and must be repaired before a full startup is attempted --
# otherwise `cryosparcm start` dies part-way with
#   OperationFailure: Our replica set config is invalid or we are not a member of it
# and leaves services holding ports, after which a retry reports
#   Starting CryoSPARC on 61000 with conflicts
# and never brings redis up, so the upgrade then fails on
#   ConnectionError: Error 111 connecting to localhost:<base+4>
#
# Repair it with the database alone running, then stop everything for a clean
# slate before the real startup.
log "Repairing the replica-set configuration for the new port..."
if ! cryosparcm start database >>"${LOG_FILE}" 2>&1; then
    fail "Could not start the database to repair its replica-set configuration.
See ${LOG_FILE}."
    exit 1
fi
if ! cryosparcm database fixport >>"${LOG_FILE}" 2>&1; then
    log "WARNING: 'database fixport' returned non-zero; continuing anyway."
fi
cryosparcm stop >>"${LOG_FILE}" 2>&1 || true

# The dry-run startup is not optional: it runs `database configure`, which
# creates the MongoDB auth users (cryosparc_admin / cryosparc_user, credentials
# derived from the license). This mirrors what bin/cryosparcm does for the
# database stage of its own update.
log "Starting database and core services (this creates the MongoDB auth users)..."
if ! cryosparcm start --no-startup --no-app >>"${LOG_FILE}" 2>&1; then
    fail "Could not start CryoSPARC's database and core services, so the database
was not upgraded. See ${LOG_FILE}."
    exit 1
fi

log "Running 'cryosparcm upgrade -y' -- do not interrupt this step."
if ! printf 'n\nn\n' | cryosparcm upgrade -y >>"${LOG_FILE}" 2>&1; then
    fail "The database upgrade reported an error.

This usually means CryoSPARC found data it could not validate. Continuing would
have required detaching the affected projects, which removes their database
records, so the migration stopped instead and left the decision to a human.

Your original v4 database is untouched at ${V4_DBPATH}, so you can keep
working in a CryoSPARC v4.7 session. The failed v5 copy is at ${V5_DBPATH}.
Any validation report is in ${LOG_DIR}.

Please send ${LOG_FILE} to the cryo-EM support team."
    exit 1
fi
# `cryosparcm upgrade` exits 0 while doing nothing at all if the database has no
# `running_version` recorded ("This is a new installation and database upgrade is
# not required") or already reports v5. We only get here having just copied a v4
# database in, so either outcome means the documents were NOT upgraded -- and
# silently running v5 against un-upgraded v4 data is exactly what the CryoSPARC
# guide warns against. Treat it as a failure rather than a success.
if grep -qiE 'new installation and database upgrade is not required|database upgrade is not required for this version' "${LOG_FILE}"; then
    fail "CryoSPARC declined to upgrade the database.

It reported that no upgrade was required, but a CryoSPARC v4 database was just
copied in from ${V4_DBPATH}, so the documents have NOT been migrated. Running v5
against un-upgraded v4 data risks corrupting it, so this session will not start.

This usually means the source database never recorded a version, which can
happen if that CryoSPARC instance was never fully started. Please contact the
cryo-EM support team with ${LOG_FILE}; your v4 database has not been modified."
    exit 1
fi

log "Database upgrade completed."

###
# 5. Validate
###
# Echo the upgrade's own summary lines so the log is self-contained.
grep -hiE 'users (validated|upgraded)|projects (passed|upgraded)|targets (validated|upgraded)|lanes (validated|upgraded)|Successfully completed database upgrade|Detected [0-9]+ cases' "${LOG_FILE}" 2>/dev/null \
    | sed 's/^/    /' | while IFS= read -r line; do log "upgrade:${line}"; done

log "Validating migrated database..."
if cryosparcm database check >>"${LOG_FILE}" 2>&1; then
    log "Database validation passed."
elif [ "${LOCK_WAS_STALE}" = "1" ]; then
    # The source was not cleanly shut down, so a failed check here could mean the
    # copy is genuinely inconsistent. Do not hand the user a suspect instance.
    fail "The migrated database did not pass 'cryosparcm database check', and the
v4 database it was copied from had not been shut down cleanly. The copy may be
inconsistent, so this session will not start.

Your original v4 database is untouched at ${V4_DBPATH}. Starting a CryoSPARC
v4.7 session and exiting it cleanly, then retrying, will usually resolve this.
See ${LOG_FILE}."
    exit 1
else
    # A check failure is worth surfacing but is not proof of data loss, and the
    # v4 original is still intact either way. Let the user in so they can look.
    log "WARNING: 'cryosparcm database check' reported problems; see ${LOG_FILE}."
fi

# Reports are only written when there were errors or parameter changes.
for report in "${LOG_DIR}"/validation_results_*.json "${LOG_DIR}"/upgrade_results_*.json; do
    [ -f "${report}" ] && log "Upgrade report: ${report}"
done

set_state "done"
log "Migration finished successfully."
notify "CryoSPARC v5 database migration completed successfully.

Your original v4 database is still at ${V4_DBPATH} and was not modified.
Once you are satisfied that v5 works, you may delete it to reclaim space.

Log: ${LOG_FILE}"
exit 0
