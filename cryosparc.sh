#!/bin/bash -x
# Start a per-user CryoSPARC v5 instance inside the container.
#
# v5 replaced the v4 command line interface, so the command names here
# differ from the v4 version of this script (see git history):
#   cryosparcm fixdbport   -> cryosparcm database fixport
#   cryosparcm createuser  -> cryosparcm user create
#   cryosparcm resetpassword -> cryosparcm user resetpassword
#   cryosparcw connect     -> cryosparcm worker connect
#   cli get_scheduler_targets()/remove_scheduler_target_node() -> no equivalent;
#       see purge_scheduler_targets() below.

export PATH=${CRYOSPARC_MASTER_DIR}/bin:${CRYOSPARC_WORKER_DIR}/bin:${CRYOSPARC_MASTER_DIR}/.pixi/envs/master/bin:$PATH
export HOME=${HOME:-$USER_HOMEDIR}
export LSCRATCH=${LSCRATCH:-/lscratch/$USER}

###
# Where the user's desktop actually is.
#
# Ask xdg-user-dir, because that performs the same lookup the desktop itself
# does: it reads ~/.config/user-dirs.dirs. Exporting XDG_DESKTOP_DIR (as the
# Open OnDemand xfce script does) has NO effect on xfdesktop, so trusting that
# variable put our launcher in a directory nobody was looking at.
#
# On S3DF user-dirs.dirs currently reads XDG_DESKTOP_DIR="$HOME/", i.e. the
# desktop surface is the home directory itself, so that is where the launcher
# has to go to be visible. The remaining candidates are fallbacks for sessions
# without xdg-user-dir or without that config.
###
resolve_desktop_dir() {
  local candidate
  for candidate in "$(xdg-user-dir DESKTOP 2>/dev/null)" \
                   "${XDG_DESKTOP_DIR}" \
                   "${LSCRATCH:+${LSCRATCH}/Desktop}" \
                   "${HOME}/Desktop"; do
    candidate=${candidate%/}
    [ -n "${candidate}" ] || continue
    if mkdir -p "${candidate}" 2>/dev/null && [ -w "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}
export CRYOSPARC_DESKTOP_DIR=$(resolve_desktop_dir)
echo "CRYOSPARC_DESKTOP_DIR=${CRYOSPARC_DESKTOP_DIR:-<none writable>}"

###
# master initialization
###
export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME:-localhost}
if [ "${CRYOSPARC_LICENSE_ID}" == "" ]; then
  echo "CRYOSPARC_LICENSE_ID required to continue..."
  exit 127
fi
# deal with multiple licenses
if [ -z "${CRYOSPARC_LICENSE_ID##*,*}" ]; then
  IFS=',' read -r -a licenses <<< "$CRYOSPARC_LICENSE_ID"
  for index in "${!licenses[@]}"
  do
    echo "$index ${licenses[index]}"
  done
  CRYOSPARC_LICENSE_ID=${licenses[${HOSTNAME##*-}]}
fi

CRYOSPARC_BASE_PORT=${CRYOSPARC_BASE_PORT:-"61000"}
export CRYOSPARC_SUPERVISOR_SOCK_FILE="${LSCRATCH}/cryosparc-supervisor.sock"

echo "Starting cryosparc master..."
cd ${CRYOSPARC_MASTER_DIR}
# modify configuration
printf "%s\n" "1,\$s/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s|^export CRYOSPARC_DB_PATH=.*$|export CRYOSPARC_DB_PATH=${CRYOSPARC_DATADIR}/cryosparc_database|g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s/^export CRYOSPARC_BASE_PORT=.*$/export CRYOSPARC_BASE_PORT=${CRYOSPARC_BASE_PORT}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
echo "export CRYOSPARC_SUPERVISOR_SOCK_FILE=${CRYOSPARC_SUPERVISOR_SOCK_FILE}" >> ${CRYOSPARC_MASTER_DIR}/config.sh
echo "export CRYOSPARC_MONGO_EXTRA_FLAGS=\"  --unixSocketPrefix=${LSCRATCH}\"" >> ${CRYOSPARC_MASTER_DIR}/config.sh
if ! grep -q 'CRYOSPARC_FORCE_HOSTNAME=true' ${CRYOSPARC_MASTER_DIR}/config.sh; then
  echo 'export CRYOSPARC_FORCE_HOSTNAME=true' >> ${CRYOSPARC_MASTER_DIR}/config.sh
fi
echo '====='
cat ${CRYOSPARC_MASTER_DIR}/config.sh
echo '====='

###
# database migration from v4 (must run with the user's own license already in
# config.sh -- the v4->v5 upgrade authenticates against MongoDB using it)
###
if ! /usr/local/bin/cryosparc_db_migrate.sh; then
  echo "CryoSPARC v5 database migration failed; refusing to start." >&2
  echo "See ${CRYOSPARC_DATADIR}/run/ for the migration log." >&2
  exit 1
fi

# envs
THIS_USER=$(whoami)
THIS_USER_SUFFIX=${USER_SUFFIX:-'slac.stanford.edu'}
ACCOUNT="${THIS_USER}@${THIS_USER_SUFFIX}"
rm -f "${SOCK_FILE}" || true

export CRYOSPARC_MONGO_EXTRA_FLAGS="  --unixSocketPrefix ${LSCRATCH}"
cryosparcm start database
cryosparcm database fixport
cryosparcm restart

# creat cryosparc local accounts
create_account() {
  local account=$1;
  local password=$2;
  local name=$3;
  cryosparcm user create --email ${account} --password ${password} --username ${name} \
    --firstname ${name} --lastname ${name} --role admin;
  cryosparcm user resetpassword --email ${account} --password ${password};
}
export -f create_account
# always set the password to license
create_account ${ACCOUNT} "${CRYOSPARC_PASSWORD:-${CRYOSPARC_LICENSE_ID}}" "${THIS_USER}"
# add additional
if [ -e "/init.d/accounts" ]; then
  cat /init.d/accounts | xargs -n3 bash -c 'create_account "$0" "$1" "$2"'
fi

# need to restart to get login prompt
cryosparcm start database
cryosparcm database fixport
cryosparcm restart

# `cryosparcm restart` can return without the database actually being up (a
# stale replica-set config, a port conflict, a failed mongod spawn). This used to
# print "Success" unconditionally, so a dead instance looked like a healthy one.
# Probe the API instead of trusting the exit status.
wait_for_master() {
  local tries=0
  until cryosparcm cli "1+1" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "${tries}" -ge 36 ]; then
      return 1
    fi
    sleep 5
  done
}

if wait_for_master; then
  echo "Success starting cryosparc master!"
else
  echo "########################################################################"
  echo "ERROR: CryoSPARC did not finish starting. The web interface will not load."
  echo "       Service status:"
  cryosparcm status 2>&1 | sed -n '/process status/,/^───/p' || true
  echo "       Logs: ${CRYOSPARC_DATADIR}/run/{database,api,command_vis}.log"
  echo "########################################################################"
  {
    echo "CryoSPARC failed to start."
    echo
    echo "Service status and errors are in:"
    echo "  ${CRYOSPARC_DATADIR}/run/database.log"
    echo "  ${CRYOSPARC_DATADIR}/run/api.log"
    echo
    echo "Please send those to the cryo-EM support team."
  } > "${CRYOSPARC_DESKTOP_DIR:-${HOME}/Desktop}/CRYOSPARC-FAILED-TO-START.txt" 2>/dev/null || true
fi

###
# Remove scheduler targets left behind by previous sessions.
#
# Every Slurm allocation gives this container a new hostname, so without this the
# user's lane list fills up with dead workers.
#
# v4 enumerated targets with `cryosparcm cli 'get_scheduler_targets()'`, which v5
# removed. v5 still has `cryosparcm cli <python expr>`, which evaluates against
# the database and prints JSON, so we read the targets document directly --
# exact, rather than scraping the `cryosparcm resources` table. Targets live in a
# single doc: db.sched_config{name:"targets"}.value[], each with a name and a
# type of "node" or "cluster", which decides how it has to be removed.
###
TARGETS_EXPR="[[t['name'], (t.get('config') or t).get('type')] for t in (db.sched_config.find_one({'name':'targets'}) or {}).get('value',[])]"

purge_scheduler_targets() {
  local targets name type
  targets=$(cryosparcm cli "${TARGETS_EXPR}" 2>/dev/null)

  if [ -z "${targets}" ] || ! echo "${targets}" | jq -e . >/dev/null 2>&1; then
    echo "WARNING: could not enumerate scheduler targets via 'cryosparcm cli'."
    echo "WARNING: falling back to removing only the lanes we register ourselves;"
    echo "WARNING: stale workers from previous sessions may remain in the lane list."
    for info in /app/slurm/*/cluster_info.json; do
      [ -f "${info}" ] || continue
      name=$(jq -r '.name' "${info}")
      [ -n "${name}" ] && [ "${name}" != "null" ] && cryosparcm cluster remove "${name}" || true
    done
    return
  fi

  while IFS=$'\t' read -r name type; do
    [ -n "${name}" ] || continue
    case "${type}" in
      cluster) echo "Removing stale cluster lane '${name}'..."; cryosparcm cluster remove "${name}" || true ;;
      node)    echo "Disconnecting stale worker '${name}'...";   cryosparcm worker disconnect --worker "${name}" || true ;;
      *)       echo "Skipping target '${name}' of unknown type '${type}'." ;;
    esac
  done < <(echo "${targets}" | jq -r '.[] | @tsv')
}
purge_scheduler_targets

# add additional job lanes
if [ "${CRYOSPACE_ADD_JOB_LANES}" == "1" ] && [ -d /app/slurm ]; then
  echo "Registering job lanes..."
  for i in `ls -1 /app/slurm/`; do
    cryosparcm cluster connect --info /app/slurm/$i/cluster_info.json \
                               --script /app/slurm/$i/cluster_script.sh
  done
  cd ${CRYOSPARC_MASTER_DIR}
elif [ "${CRYOSPACE_ADD_JOB_LANES}" == "1" ]; then
  echo "WARNING: CRYOSPACE_ADD_JOB_LANES=1 but /app/slurm is not present in this"
  echo "WARNING: image, so no cluster lanes were registered."
fi

# local worker
if [ "${CRYOSPARC_LOCAL_WORKER}" == "1" ]; then
  echo "Starting cryosparc local worker for ${CRYOSPARC_MASTER_HOSTNAME}..."
  export CRYOSPARC_CACHE_DIR=${CRYOSPARC_CACHE_DIR:-"/lscratch/${THIS_USER}/cryosparc"}
  CRYOSPARC_CACHE_DIR=${CRYOSPARC_CACHE_DIR%/}
  # v5's `cryosparcw connect` rejects a --ssdpath that does not exist
  # ("Invalid value for '--ssdpath': Directory ... does not exist"), so a cache
  # directory we failed to create means no compute target at all.
  if ! mkdir -p "${CRYOSPARC_CACHE_DIR}"; then
    echo "ERROR: could not create the SSD cache directory ${CRYOSPARC_CACHE_DIR}." >&2
    echo "       CryoSPARC's local worker cannot be registered without it." >&2
  fi
  GPU_OPT=""
  if [ ! -z $CRYOSPARC_WORKER_NOGPU ]; then
    GPU_OPT="--no-gpu"
  fi
  SSD_OPTS="--ssdpath ${CRYOSPARC_CACHE_DIR} --ssdquota ${CRYOSPARC_CACHE_QUOTA:-2500000} --ssdreserve ${CRYOSPARC_CACHE_FREE:-5000}"
  if [ ! -z $CRYOSPARC_WORKER_NOSSD ]; then
    SSD_OPTS=""
  fi
  if cryosparcm worker connect --path ${CRYOSPARC_WORKER_DIR} \
                              --worker ${CRYOSPARC_MASTER_HOSTNAME} \
                              ${SSD_OPTS} ${GPU_OPT}; then
    echo "Success starting cryosparc worker"
  else
    echo "####################################################################"
    echo "ERROR: could not register the local CryoSPARC worker. Jobs cannot be"
    echo "       queued to this session. See the error above."
    echo "####################################################################"
  fi
fi

###
# create firefox startup
###
export CRYOSPARC_BASE_PORT=$(cat ${CRYOSPARC_DATADIR}/config.sh | awk '/CRYOSPARC_BASE_PORT/{ split($2,a,"="); print a[2] }')

# Put the URL straight into the desktop entry's Exec line.
#
# This used to write a helper script to $LSCRATCH and symlink it onto the
# desktop, with the entry running "Exec=bash cryosparc_launcher.sh". That could
# never work: desktop entries are not launched with the desktop folder as their
# working directory, so the relative filename resolved to nothing -- and the
# helper script was never made executable either. Substituting the port into an
# absolute Exec removes both faults and leaves a single file on the desktop.
if [ -n "${CRYOSPARC_DESKTOP_DIR}" ]; then
  sed "s|__BASE_PORT__|${CRYOSPARC_BASE_PORT}|g" /cryosparc.desktop \
    > "${CRYOSPARC_DESKTOP_DIR}/cryosparc.desktop"
  chmod +x "${CRYOSPARC_DESKTOP_DIR}/cryosparc.desktop"
  # Remove the artefacts of the old scheme, both from the directory we now use
  # and from $HOME/Desktop, where earlier versions wrote them. Only our own
  # files are touched; the directory itself is left alone.
  for stale in "${CRYOSPARC_DESKTOP_DIR}" "${HOME}/Desktop"; do
    rm -f "${stale}/cryosparc_launcher.sh" "${stale}/CRYOSPARC-MIGRATION.txt" 2>/dev/null || true
  done
else
  echo "WARNING: no writable desktop directory; the CryoSPARC launcher icon was not created."
  echo "WARNING: open http://localhost:${CRYOSPARC_BASE_PORT} in the browser instead."
fi

###
# monitor forever
#
# This loop never returns, so it has to stay last -- it previously sat ahead of
# the launcher-icon setup, which therefore never ran when CRYOSPARC_TAIL_LOGS=1.
###
if [ "$CRYOSPARC_TAIL_LOGS" == "1" ]; then
  echo "tailing logs..."
  while [ 1 ]; do
    tail -f ${CRYOSPARC_MASTER_DIR}/run/command_core.log
  done
fi
