#!/bin/bash -x

export PATH=${CRYOSPARC_MASTER_DIR}/bin:${CRYOSPARC_WORKER_DIR}/bin:${CRYOSPARC_MASTER_DIR}/deps/anaconda/bin/:$PATH
export HOME=${HOME:-$USER_HOMEDIR}
export LSCRATCH=${LSCRATCH:-/lscratch/$USER}

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

CRYOSPARC_BASE_PORT=${CRYOSPARC_BASE_PORT:-"39000"}
export CRYOSPARC_SUPERVISOR_SOCK_FILE="${LSCRATCH}/cryosparc-supervisor.sock" 

echo "Starting cryosparc master..."
cd ${CRYOSPARC_MASTER_DIR}
# modify configuration
printf "%s\n" "1,\$s/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s|^export CRYOSPARC_DB_PATH=.*$|export CRYOSPARC_DB_PATH=${CRYOSPARC_DATADIR}/cryosparc_database|g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s/^export CRYOSPARC_BASE_PORT=.*$/export CRYOSPARC_BASE_PORT=${CRYOSPARC_BASE_PORT}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
#printf "%s\n" "export CRYOSPARC_SUPERVISOR_SOCK_FILE=${CRYOSPARC_SUPERVISOR_SOCK_FILE}" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
#printf "%s\n" "export CRYOSPARC_MONGO_EXTRA_FLAGS=\"  --unixSocketPrefix=${LSCRATCH}\"" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
echo "export CRYOSPARC_SUPERVISOR_SOCK_FILE=${CRYOSPARC_SUPERVISOR_SOCK_FILE}" >> ${CRYOSPARC_MASTER_DIR}/config.sh
echo "export CRYOSPARC_MONGO_EXTRA_FLAGS=\"  --unixSocketPrefix=${LSCRATCH}\"" >> ${CRYOSPARC_MASTER_DIR}/config.sh
if ! grep -q 'CRYOSPARC_FORCE_HOSTNAME=true' ${CRYOSPARC_MASTER_DIR}/config.sh; then
  echo 'export CRYOSPARC_FORCE_HOSTNAME=true' >> ${CRYOSPARC_MASTER_DIR}/config.sh
fi
echo '====='
cat ${CRYOSPARC_MASTER_DIR}/config.sh
echo '====='

# modify mongo path
#sed -i 's|MONGO_URL="mongodb://%(ENV_CRYOSPARC_MASTER_HOSTNAME)s:%(ENV_CRYOSPARC_MONGO_PORT)s|MONGO_URL=mongodb://cryosparc-fpoitevi:%(ENV_CRYOSPARC_MONGO_PORT)s|g' ${CRYOSPARC_MASTER_DIR}/supervisord.conf
#sed -i 's|MONGO_OPLOG_URL="mongodb://%(ENV_CRYOSPARC_MASTER_HOSTNAME)s:%(ENV_CRYOSPARC_MONGO_PORT)s|MONGO_OPLOG_URL="mongodb://cryosparc-fpoitevi:%(ENV_CRYOSPARC_MONGO_PORT)s|g' ${CRYOSPARC_MASTER_DIR}/supervisord.conf
#sed -i 's|ROOT_URL="http://%(ENV_CRYOSPARC_MASTER_HOSTNAME)s:|ROOT_URL="http://cryosparc-fpoitevi:|g' ${CRYOSPARC_MASTER_DIR}/supervisord.conf
#sed -i 's|file=%(ENV_CRYOSPARC_SUPERVISOR_SOCK_FILE)s|file=/lscratch/%(ENV_CRYOSPARC_SUPERVISOR_SOCK_FILE)s|g' ${CRYOSPARC_MASTER_DIR}/supervisord.conf

# envs
THIS_USER=$(whoami)
THIS_USER_SUFFIX=${USER_SUFFIX:-'slac.stanford.edu'}
ACCOUNT="${THIS_USER}@${THIS_USER_SUFFIX}"
rm -f "${SOCK_FILE}" || true
cryosparcm start database
cryosparcm fixdbport
cryosparcm restart

# ensure that the mongo replset is correct
MONGO_PORT=$(( $CRYOSPARC_BASE_PORT + 1 ))
export CRYOSPARC_MONGO_EXTRA_FLAGS="  --unixSocketPrefix ${LSCRATCH}"
${CRYOSPARC_MASTER_DIR}/bin/cryosparcm start database
${CRYOSPARC_MASTER_DIR}/bin/cryosparcm fixdbport
${CRYOSPARC_MASTER_DIR}/bin/cryosparcm restart

# creat cryosparc local accounts
create_account() {
  local account=$1;
  local password=$2;
  local name=$3;
  cryosparcm createuser    --email ${account} --password ${password} --username ${name} --firstname ${name} --lastname ${name};
  cryosparcm resetpassword --email ${account} --password ${password};
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
cryosparcm fixdbport
cryosparcm restart

echo "Success starting cryosparc master!"

# remove all existing worker threads
${CRYOSPARC_MASTER_DIR}/bin/cryosparcm cli 'get_scheduler_targets()'  | python -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | jq '.[].name' | sed 's:"::g' | xargs -n1 -I \{\} ${CRYOSPARC_MASTER_DIR}/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'

# add additional job lanes
if [ "${CRYOSPACE_ADD_JOB_LANES}" == "1" ]; then
  echo "Registering job lanes..."
  for i in `ls -1 /app/slurm/`; do
    cd /app/slurm/$i
    ${CRYOSPARC_MASTER_DIR}/bin/cryosparcm cluster connect
  done
  cd ${CRYOSPARC_MASTER_DIR}
fi

# local worker
if [ "${CRYOSPARC_LOCAL_WORKER}" == "1" ]; then
  echo "Starting cryosparc local worker for ${CRYOSPARC_MASTER_HOSTNAME}..."
  export CRYOSPARC_CACHE_DIR=${CRYOSPARC_CACHE_DIR:-"/lscratch/${THIS_USER}/cryosparc/"}
  mkdir -p ${CRYOSPARC_CACHE_DIR}
  NOGPU=""
  if [ ! -z $CRYOSPARC_WORKER_NOGPU ]; then
    NOGPU="--nogpu"
  fi
  SSD_OPTS="--ssdpath ${CRYOSPARC_CACHE_DIR}/ --ssdquota ${CRYOSPARC_CACHE_QUOTA:-2500000} --ssdreserve ${CRYOSPARC_CACHE_FREE:-5000}"
  if [ ! -z $CRYOSPARC_WORKER_NOSSD ]; then
    SSD_OPTS="--nossd"
  fi
  ${CRYOSPARC_WORKER_DIR}/bin/cryosparcw connect --worker ${CRYOSPARC_MASTER_HOSTNAME} --master ${CRYOSPARC_MASTER_HOSTNAME} --port ${CRYOSPARC_BASE_PORT} ${SSD_OPTS} ${NOGPU}

  echo "Success starting cryosparc worker"
fi

###
# monitor forever
###
if [ "$CRYOSPARC_TAIL_LOGS" == "1" ]; then
  echo "tailing logs..."
  while [ 1 ]; do
    tail -f ${CRYOSPARC_MASTER_DIR}/run/command_core.log
  done
fi

###
# create firefox startup
###
export CRYOSPARC_BASE_PORT=$(cat $HOME/cryosparc/config.sh | awk '/CRYOSPARC_BASE_PORT/{ split($2,a,"="); print a[2] }')
echo "/usr/bin/firefox http://localhost:${CRYOSPARC_BASE_PORT}" > ${LSCRATCH}/cryosparc_launcher.sh
cp /cryosparc.desktop ${HOME}/Desktop/cryosparc.desktop 
chmod +x ${HOME}/Desktop/cryosparc.desktop
ln -sfn ${LSCRATCH}/cryosparc_launcher.sh "${HOME}/Desktop/cryosparc_launcher.sh"
