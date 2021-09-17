#!/bin/bash

source ./pipeline.data
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}


if  kubectl get ing | grep  ${CANARY_INGRESS_NAME};
then
    echo "Removing the canary deployment....."
    kubectl delete -f ${CANARY_DEPLOYMENT_FILE}
else 
    echo "Canary Deployment not found....."
fi


sleep 5 