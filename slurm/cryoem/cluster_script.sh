#!/bin/bash -l

## {{ project_dir_abs }}    - absolute path to the project dir
## {{ job_creator }}        - name of the user that created the job (may contain spaces)
## {{ cryosparc_username }} - cryosparc username of the user that created the job (usually an email)

#SBATCH -A cryoem -p cryoem
#SBATCH -n {{ num_cpu }}
#SBATCH -N 1
#SBATCH --gpus {{ num_gpu }}
#SBATCH --mem={{ (ram_gb*1000)|int }}MB             
#SBATCH --job-name cryosparc_{{ project_uid }}_{{ job_uid }}
#SBATCH -o {{ job_dir_abs }}/job-%j.out
#SBATCH -e {{ job_dir_abs }}/job-%j.err

LD_PRELOAD=""
nvidia-smi
echo "CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES}
echo "CRYOSPARC_VERSION="${CRYOSPARC_VERSION}

export TMPDIR="/scratch/${USER}/cryosparc/"
#{{ project_uid }}/{{ job_uid }}/"
echo "TMPDIR="$TMPDIR
mkdir -p ${TMPDIR}

# load cryosarc
source /etc/profile.d/modules.sh
export MODULEPATH=/afs/slac/package/singularity/modulefiles
module load cryosparc/${CRYOSPARC_VERSION:1}
# {{ run_cmd }}
{{ worker_bin_path }} run {{ run_args }} --ssd "${TMPDIR}" > {{ job_log_path_abs }} 2>&1

