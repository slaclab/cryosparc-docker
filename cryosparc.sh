#!/bin/bash  -xe

#echo '================================'
#ls -lah /gpfs
#ls -lah /gpfs/slac/
#ls -lah /gpfs/slac/cryo/fs1
#echo '================================'

export PATH=${CRYOSPARC_MASTER_DIR}/bin:${CRYOSPARC_WORKER_DIR}/bin:${CRYOSPARC_MASTER_DIR}/deps/anaconda/bin/:$PATH
export HOME=${USER_HOMEDIR}

export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME:-localhost}

if [ "${CRYOSPARC_ROLE}" == "master" ]; then

  ###
  # master initiation
  ###
  echo "Starting cryosparc master..."

  cd ${CRYOSPARC_MASTER_DIR}
  # modify configuration
  # ls -lah ${CRYOSPARC_MASTER_DIR}/config.sh
  sed -i --follow-symlinks 's/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}/g' ${CRYOSPARC_MASTER_DIR}/config.sh
  #sed -i --follow-symlinks 's/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${HOSTNAME}/g' ${CRYOSPARC_MASTER_DIR}/config.sh
  sed -i --follow-symlinks 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g' ${CRYOSPARC_MASTER_DIR}/config.sh
  sed -i --follow-symlinks 's/^export CRYOSPARC_DB_PATH=.*$/export CRYOSPARC_DB_PATH=${CRYOSPARC_DATADIR}\/cryosparc2_database/g' ${CRYOSPARC_MASTER_DIR}/config.sh
  
  # envs
  echo "Starting cryoSPARC in ${CRYOSPARC_MASTER_DIR} with..."
  SOCK_FILE=$(cryosparcm env | grep CRYOSPARC_SUPERVISOR_SOCK_FILE | sed 's/^.*CRYOSPARC_SUPERVISOR_SOCK_FILE=//' | sed 's/"//g')
  rm -f "${SOCK_FILE}" || true
  cryosparcm restart

  # always set the passwrod to license
  cryosparcm createuser --email $(whoami)@slac.stanford.edu --password "${CRYOSPARC_LICENSE_ID}" --name "User"
  cryosparcm resetpassword --email $(whoami)@slac.stanford.edu --password "${CRYOSPARC_LICENSE_ID}"
  
  # need to restart to get login prompt
  cryosparcm restart

  # remove all existing worker threads
  /app/cryosparc2_master/bin/cryosparcm cli 'get_scheduler_targets()'  | python -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | jq '.[].name' | sed 's:"::g' | xargs -n1 -I \{\} /app/cryosparc2_master/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'

else

  ###
  # worker initiation
  ###
  echo "Starting cryosparc worker..."

  export TMPDIR=${TMPDIR:-/scratch/$(whoami)}

  cd ${CRYOSPARC_WORKER_DIR}
  sed -i --follow-symlinks 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID}/g' ${CRYOSPARC_WORKER_DIR}/config.sh
  sed -i --follow-symlinks 's/^export CRYOSPARC_MASTER_HOSTNAME=.*$/export CRYOSPARC_MASTER_HOSTNAME=${CRYOSPARC_MASTER_HOSTNAME}/g' ${CRYOSPARC_WORKER_DIR}/config.sh
  
  # start worker
  mkdir -p $TMPDIR
  
  #echo cryosparcw connect --update --worker localhost --master cryosparc-${USER} --ssdpath /scratch/$(whoami)/
  #cryosparcw connect --update --worker localhost --master cryosparc-${USER} --ssdpath /scratch/$(whoami)/
  #if [ $? == 1 ]; then
  /app/cryosparc2_worker/bin/cryosparcw connect --worker localhost --master cryosparc-api-$(whoami) --ssdpath $TMPDIR/
  #fi

fi
 
###
# monitor forever
###
echo "done... tailing logs..."
tail -f ${CRYOSPARC_MASTER_DIR}/run/command_core.log
