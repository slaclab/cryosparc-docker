#!/bin/bash
# End the desktop session once CryoSPARC has had no queued or active jobs for a
# given idle period, so abandoned sessions stop holding GPUs.
#
# v5 note: `cryosparcm jobstatus` became `cryosparcm job status`, and the output
# changed shape. v4 printed a "Jobs running:" header with the count on the NEXT
# line. v5 prints one line per status, count on the SAME line:
#     Jobs queued: 0
#     Jobs launched: 0
#     Jobs started: 0
#     Jobs running: 2
#     Jobs waiting: 0
# so we sum the statuses rather than reading a single number.

CRYOSPARCM=/app/cryosparc_master/bin/cryosparcm

cull () {
    echo "$(date -d "now" +"%Y-%m-%d %H:%M:%S"): Culling xfce desktop session due to CPU/GPU resource inactivity..."
    /usr/bin/pkill -9 xfce4-session
}

usage () {
    echo "No maximum timeout specified. Use any valid date string format accepted by date(1) -d."
    echo "Example: cryosparc_idle_culler.sh \"2 hours\""
    exit 1
}

# Echoes the number of jobs actively holding this allocation, or "unknown" if the
# output could not be parsed at all. Distinguishing the two matters: treating an
# unreadable status as "zero jobs" would cull sessions that are busy.
#
# "unknown" is decided from the unfiltered output, so a session whose only jobs
# are queued still reports 0 (and is therefore cullable) rather than "unknown".
count_active_jobs () {
    local output parsed total
    output=$("${CRYOSPARCM}" job status 2>/dev/null)

    parsed=$(printf '%s\n' "${output}" | sed -n 's/^Jobs [a-z]\{1,\}:[[:space:]]*\([0-9]\{1,\}\).*$/\1/p')
    if [ -z "${parsed}" ]; then
        echo "unknown"
        return
    fi

    # Sum every reported status except "queued". Matching the remaining statuses
    # generically rather than listing them means a new alive status introduced by
    # a future CryoSPARC release is counted automatically, which errs towards
    # keeping a busy session rather than culling it.
    total=$(printf '%s\n' "${output}" \
        | grep -v '^Jobs queued:' \
        | sed -n 's/^Jobs [a-z]\{1,\}:[[:space:]]*\([0-9]\{1,\}\).*$/\1/p' \
        | awk '{s+=$1} END {print s+0}')
    echo "${total}"
}

if [ -z "$1" ]; then
    usage
fi

MAX_IDLE=$1
export CHECK_FILE="${LSCRATCH}/cryosparc_job_check_${SLURM_JOB_ID}"

while true; do
    JOBS_ACTIVE=$(count_active_jobs)

    if [ "${JOBS_ACTIVE}" = "unknown" ]; then
        # Could not read job status: CryoSPARC may still be starting, or the CLI
        # changed again. Assume the session is in use so we never cull during
        # real work, and make the reason visible in the log.
        echo "$(date -d "now" +"%Y-%m-%d %H:%M:%S"): WARNING: could not parse '${CRYOSPARCM} job status'; assuming session is active and deferring cull."
        touch "${CHECK_FILE}"
    elif [ "${JOBS_ACTIVE}" -gt 0 ]; then
        echo "$(date -d "now" +"%Y-%m-%d %H:%M:%S"): Found ${JOBS_ACTIVE} running CryoSPARC jobs, updating ${CHECK_FILE}..."
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
