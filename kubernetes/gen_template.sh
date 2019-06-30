#!/bin/bash

# set -x

CONFIG_FILE="ENVIRONMENT"
if [ -n "${1}" ]; then
    CONFIG_FILE="${1}"
fi

# import key value pairs
source ./${CONFIG_FILE}

# stolen from https://starkandwayne.com/blog/bashing-your-yaml/
function gen_template() {
    rm -f final.yaml temp.yaml  
    ( echo "cat <<EOF >final.yaml";
      cat $1;
      echo "EOF";
    ) >temp.yaml
    . temp.yaml
    cat final.yaml
    rm -f final.yaml temp.yaml  
}

gen_template "${2}"
