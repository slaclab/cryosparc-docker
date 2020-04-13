#!/bin/bash -xe

# ensure we have a cryosparc directory under home
export CRYOSPARC_DATADIR=${HOME}/cryosparc-v2
echo "Creating cryosparc datadir ${CRYOSPARC_DATADIR}..."
mkdir -p ${CRYOSPARC_DATADIR}
mkdir -p ${CRYOSPARC_DATADIR}/run
mkdir -p ${CRYOSPARC_DATADIR}/cryosparc2_database

export PATH=${CRYOSPARC_MASTER_DIR}/bin:${CRYOSPARC_WORKER_DIR}/bin:${CRYOSPARC_MASTER_DIR}/deps/anaconda/bin/:$PATH

export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME:-$(hostname -s)}
echo "setting CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}"

###
# master initiation
###
CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID:-$1}
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
THIS_USER=$(whoami)
THIS_USER_SUFFIX=${USER_SUFFIX:-'@slac.stanford.edu'}
echo "Starting cryoSPARC in ${CRYOSPARC_MASTER_DIR} as ${THIS_USER}${THIS_USER_SUFFIx} with..."
SOCK_FILE=$(cryosparcm env | grep CRYOSPARC_SUPERVISOR_SOCK_FILE | sed 's/^.*CRYOSPARC_SUPERVISOR_SOCK_FILE=//' | sed 's/"//g')
rm -f "${SOCK_FILE}" || true
cryosparcm restart

# always set the password to license
cryosparcm createuser    --email ${THIS_USER}${THIS_USER_SUFFIX} --password "${CRYOSPARC_LICENSE_ID}" --name "User"
cryosparcm resetpassword --email ${THIS_USER}${THIS_USER_SUFFIX} --password "${CRYOSPARC_LICENSE_ID}"

# need to restart to get login prompt
cryosparcm restart

# remove all existing lanes and register standard lanes
echo "Registering job lanes..."
/app/cryosparc2_master/bin/cryosparcm cli 'get_scheduler_targets()'  | python -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | jq '.[].name' | sed 's:"::g' | xargs -n1 -I \{\} /app/cryosparc2_master/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'
# add slurm lanes
for i in `ls -1 /app/slurm/`; do
  cd /app/slurm/$i
  /app/cryosparc2_master/bin/cryosparcm cluster connect
done
cd ${CRYOSPARC_MASTER_DIR}

echo "Success starting cryosparc master!"

###
# worker initiation
###
echo "Starting cryosparc worker for ${CRYOSPARC_MASTER_HOSTNAME}..."
export TMPDIR=${TMPDIR:-"/scratch/${THIS_USER}"}/cryosparc/
mkdir -p ${TMPDIR}

cd ${CRYOSPARC_WORKER_DIR}
# assume same config file
#printf "%s\n" "1,\$s/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g" wq | ed -s ${CRYOSPARC_WORKER_DIR}/config.sh
#printf "%s\n" "1,\$s/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}/g" wq | ed -s ${CRYOSPARC_WORKER_DIR}/config.sh

# start worker
#/app/cryosparc2_worker/bin/cryosparcw connect --worker localhost --master cryosparc-api-$(whoami) --ssdpath $TMPDIR/
#TODO: delete existing workers first...?
/app/cryosparc2_worker/bin/cryosparcw connect --worker ${CRYOSPARC_MASTER_HOSTNAME} --master ${CRYOSPARC_MASTER_HOSTNAME} --ssdpath $TMPDIR/

###
# monitor forever
###
echo "Success starting cryosparc worker!"

# should probably catch kill to terminate the instance
while :
do
  echo 'heartbeat...'
  sleep 300
done
