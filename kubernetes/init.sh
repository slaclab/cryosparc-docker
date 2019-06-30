#!/bin/sh

source ./PROD
kubectl create namespace ${namespace}
./gen_template.sh PROD storage.yaml |  kubectl -n ${namespace} create -f -
