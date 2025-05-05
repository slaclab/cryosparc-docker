#!/bin/bash 

cull () {
    echo "$(date -d "now" +"%Y-%m-%d %H:%M:%S"): Culling xfce desktop session due to CPU/GPU resource inactivity..."
    /usr/bin/pkill -9 xfce4-session
}

usage () {
    echo "No maximum timeout specified. Use any valid date string format accepted by date(1) -d."
    echo "Example: cryosparc_idle_culler.sh \"2 hours\""
    exit 1
}

if [ -z "$1" ]; then 
    usage
fi

MAX_IDLE=$1
export CHECK_FILE="${LSCRATCH}/cryosparc_job_check_${SLURM_JOB_ID}"

while true; do
    export JOBS_RUNNING=$(/app/cryosparc_master/bin/cryosparcm jobstatus | grep -A 1 "Jobs running:" | grep -v "Jobs running:")

    if [ "${JOBS_RUNNING}" -gt 0 ]; then
        echo "$(date -d "now" +"%Y-%m-%d %H:%M:%S"): Found running CryoSPARC jobs, updating ${CHECK_FILE}..."
        touch "${CHECK_FILE}"
    fi

    if [ -f "${CHECK_FILE}" ]; then
        export LAST_CHECK=$(date -d "$(date -r "${CHECK_FILE}")" +"%s")
        export CUTOFF=$(date -d "-${MAX_IDLE}" +"%s")
        if [ "${CUTOFF}" -ge "${LAST_CHECK}" ]; then 
            echo "$(date -d "now" +"%Y-%m-%d %H:%M:%S"): No running CryoSPARC jobs found for ${MAX_IDLE}, ending session."
            cull
        fi
    else
        # create new check file if somehow removed since last check
        echo "$(date -d "now" +"%Y-%m-%d %H:%M:%S"): Checkpoint file ${CHECK_FILE} not found, creating..."
        touch "${CHECK_FILE}"
    fi

    # check every 5 mins
    sleep 5m
done
