#!/bin/bash
# Wrapper CryoSPARC invokes as its Topaz executable.
#
# Topaz lives in its own micromamba prefix (/opt/topaz) because CryoSPARC v5
# removed the Anaconda install this used to borrow. Strip any conda/python state
# leaking in from CryoSPARC's own environment so Topaz resolves its own libs.
unset _CE_CONDA CONDA_DEFAULT_ENV CONDA_EXE CONDA_PREFIX CONDA_PROMPT_MODIFIER
unset CONDA_PYTHON_EXE CONDA_SHLVL PYTHONPATH PYTHONHOME LD_PRELOAD LD_LIBRARY_PATH

TOPAZ_PREFIX=${TOPAZ_PREFIX:-/opt/topaz}
exec "${TOPAZ_PREFIX}/bin/topaz" "$@"
