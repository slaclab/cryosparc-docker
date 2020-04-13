#!/bin/bash  -xe

export PATH=${CRYOSPARC_MASTER_DIR}/bin:${CRYOSPARC_WORKER_DIR}/bin:${CRYOSPARC_MASTER_DIR}/deps/anaconda/bin/:$PATH
export HOME=${USER_HOMEDIR}

###
# master initiation
###
export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME:-localhost}
if [ "${CRYOSPARC_LICENSE_ID}" == "" ]; then
  echo "CRYOSPARC_LICENSE_ID required to continue..."
  exit 127
fi
CRYOSPARC_BASE_PORT=${CRYOSPARC_BASE_PORT:-"39000"}

echo "Starting cryosparc master..."
cd ${CRYOSPARC_MASTER_DIR}
# modify configuration
printf "%s\n" "1,\$s/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s|^export CRYOSPARC_DB_PATH=.*$|export CRYOSPARC_DB_PATH=${CRYOSPARC_DATADIR}/cryosparc2_database|g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
printf "%s\n" "1,\$s/^export CRYOSPARC_BASE_PORT=.*$/export CRYOSPARC_BASE_PORT=${CRYOSPARC_BASE_PORT}/g" wq | ed -s ${CRYOSPARC_MASTER_DIR}/config.sh
echo '====='
cat ${CRYOSPARC_MASTER_DIR}/config.sh
echo '====='

# envs
echo "Starting cryoSPARC in ${CRYOSPARC_MASTER_DIR} with..."
THIS_USER=$(whoami)
THIS_USER_SUFFIX=${USER_SUFFIX:-'@slac.stanford.edu'}
echo "Starting cryoSPARC in ${CRYOSPARC_MASTER_DIR} as ${THIS_USER}${THIS_USER_SUFFIx} with..."
SOCK_FILE=$(cryosparcm env | grep CRYOSPARC_SUPERVISOR_SOCK_FILE | sed 's/^.*CRYOSPARC_SUPERVISOR_SOCK_FILE=//' | sed 's/"//g')
rm -f "${SOCK_FILE}" || true
cryosparcm restart

# always set the passwrod to license
cryosparcm createuser --email $(whoami)@slac.stanford.edu --password "${CRYOSPARC_LICENSE_ID}" --name "User"
cryosparcm resetpassword --email $(whoami)@slac.stanford.edu --password "${CRYOSPARC_LICENSE_ID}"

# need to restart to get login prompt
cryosparcm restart

# remove all existing worker threads
echo "Registering job lanes..."
${CRYOSPARC_MASTER_DIR}/bin/cryosparcm cli 'get_scheduler_targets()'  | python -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | jq '.[].name' | sed 's:"::g' | xargs -n1 -I \{\} ${CRYOSPARC_MASTER_DIR}/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'
# add slurm lanes
for i in `ls -1 /app/slurm/`; do
  cd /app/slurm/$i
  ${CRYOSPARC_MASTER_DIR}/bin/cryosparcm cluster connect
done
cd ${CRYOSPARC_MASTER_DIR}

echo "Success starting cryosparc master!"

if [ "${CRYOSPARC_LOCAL_WORKER}" == "1" ]; then

  ###
  # worker initiation
  ###
  echo "Starting cryosparc worker cryosparc-api-${THIS_USER} for ${CRYOSPARC_MASTER_HOSTNAME}..."
  export TMPDIR=${TMPDIR:-"/scratch/${THIS_USER}/cryosparc/"}
  mkdir -p ${TMPDIR}

  cd ${CRYOSPARC_WORKER_DIR}
  #printf "%s\n" "1,\$s/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g" wq | ed -s ${CRYOSPARC_WORKER_DIR}/config.sh
  #printf "%s\n" "1,\$s/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}/g" wq | ed -s ${CRYOSPARC_WORKER_DIR}/config.sh

  # intiate
  ${CRYOSPARC_WORKER_DIR}/bin/cryosparcw connect --worker cryosparc-api-${THIS_USER} --master cryosparc-api-${THIS_USER} --ssdpath $TMPDIR/

  echo "Success starting cryosparc worker!"

fi

###
# monitor forever
###
echo "done... tailing logs..."
tail -f ${CRYOSPARC_MASTER_DIR}/run/command_core.log
