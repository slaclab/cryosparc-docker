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
sed -i --follow-symlinks 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g' ${CRYOSPARC_MASTER_DIR}/config.sh
sed -i --follow-symlinks 's/^export CRYOSPARC_DB_PATH=.*$/export CRYOSPARC_DB_PATH=${CRYOSPARC_DATADIR}\/cryosparc2_database/g' ${CRYOSPARC_MASTER_DIR}/config.sh

# envs
echo "Starting cryoSPARC in ${CRYOSPARC_MASTER_DIR} with..."
cryosparcm env

# start
cryosparcm restart

# add user
cryosparcm createuser --email $(whoami)@slac.stanford.edu --password testtest --name "JupyterHub User"

# need to restart to get login prompt
cryosparcm restart

env

###
# worker initiation
###

cd ${CRYOSPARC_WORKER_DIR}
sed -i 's/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=localhost/g' ${CRYOSPARC_WORKER_DIR}/config.sh

# start
cryosparcw connect --worker localhost --master localhost --ssdpath /scratch

###
# monitor forever
###

while [ 1 ]; do
  cryosparcm status
  # cryosparcw status
  sleep 60
done
