#!/bin/bash  -e

#echo '================================'
#ls -lah /gpfs
#ls -lah /gpfs/slac/
#ls -lah /gpfs/slac/cryo/fs1
#echo '================================'

export PATH=${CRYOSPARC_MASTER_DIR}/bin:${CRYOSPARC_WORKER_DIR}/bin:${CRYOSPARC_MASTER_DIR}/deps/anaconda/bin/:$PATH
export HOME=${USER_HOMEDIR}

###
# initiate jupyter
###
#echo "Running JupyterLab..."
#jupyter-labhub \
#     --ip='*' --port=8888 \
#     --hub-api-url=${JUPYTERHUB_API_URL} \
#     --notebook-dir=${HOME} 

# block

###
# master initiation
###

cd ${CRYOSPARC_MASTER_DIR}

# modify configuration
ls -lah ${CRYOSPARC_MASTER_DIR}/config.sh
sed -i --follow-symlinks 's/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=localhost/g' ${CRYOSPARC_MASTER_DIR}/config.sh
#sed -i --follow-symlinks 's/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${HOSTNAME}/g' ${CRYOSPARC_MASTER_DIR}/config.sh
sed -i --follow-symlinks 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g' ${CRYOSPARC_MASTER_DIR}/config.sh
sed -i --follow-symlinks 's/^export CRYOSPARC_DB_PATH=.*$/export CRYOSPARC_DB_PATH=${CRYOSPARC_DATADIR}\/cryosparc2_database/g' ${CRYOSPARC_MASTER_DIR}/config.sh

# envs
echo "Starting cryoSPARC in ${CRYOSPARC_MASTER_DIR} with..."
cryosparcm env

# start
cryosparcm restart

# add user
cryosparcm createuser --email $(whoami)@slac.stanford.edu --password "${CRYOSPARC_LICENSE_ID}" --name "User"
# always set the passwrod to license
cryosparcm resetpassword --email $(whoami)@slac.stanford.edu --password "${CRYOSPARC_LICENSE_ID}"

# need to restart to get login prompt
cryosparcm restart

###
# worker initiation
###
cd ${CRYOSPARC_WORKER_DIR}
sed -i --follow-symlinks 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g' ${CRYOSPARC_WORKER_DIR}/config.sh
sed -i --follow-symlinks 's/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${HOSTNAME}/g' ${CRYOSPARC_WORKER_DIR}/config.sh

# start worker
mkdir -p /scratch/$(whoami)

# remove all existing worker threads
/app/cryosparc2_master/bin/cryosparcm cli 'get_scheduler_targets()'  | python -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | jq '.[].name' | sed 's:"::g' | xargs -n1 -I \{\} /app/cryosparc2_master/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'

#echo cryosparcw connect --update --worker localhost --master cryosparc-${USER} --ssdpath /scratch/$(whoami)/
#cryosparcw connect --update --worker localhost --master cryosparc-${USER} --ssdpath /scratch/$(whoami)/
#if [ $? == 1 ]; then
/app/cryosparc2_worker/bin/cryosparcw connect --worker localhost --master cryosparc-api-$(whoami) --ssdpath /scratch/$(whoami)/
#fi

###
# monitor forever
###
tail -f ${CRYOSPARC_MASTER_DIR}/run/command_core.log
