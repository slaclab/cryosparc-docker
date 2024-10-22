#!/bin/bash --login

if command -v conda > /dev/null 2>&1; then
    conda deactivate > /dev/null 2>&1 || true  # ignore any errors
    conda deactivate > /dev/null 2>&1 || true  # ignore any errors
fi
unset _CE_CONDA
unset CONDA_DEFAULT_ENV
unset CONDA_EXE
unset CONDA_PREFIX
unset CONDA_PROMPT_MODIFIER
unset CONDA_PYTHON_EXE
unset CONDA_SHLVL
unset PYTHONPATH
unset LD_PRELOAD
unset LD_LIBRARY_PATH

set -euo pipefail
set +euo pipefail
export BIN_PATH=/app/cryosparc_worker/deps/anaconda/bin
${BIN_PATH}/activate topaz_env
set -euo pipefail

exec ${BIN_PATH}/topaz $@
