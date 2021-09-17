#!/bin/bash


#### Check if the canary deployment is in progress.
#### If not, then exit out the script.
#### If yes, then mark the canary app deployment with with a label 
#### name as DEPLOYMENT:STOP
#### and wait for the other running pipeline to stop.
#### Then delete the canary deployment


source ./pipeline.data
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}

TEMP_CANARY_SERVICE_FILE=canary_service.yaml
echo "STEP_SIZE  $STEP_SIZE"
echo "STEP_INTERVAL  $STEP_INTERVAL"



if  kubectl get ing | grep  ${CANARY_INGRESS_NAME};
then
    kubectl get  svc ${CANARY_NODEPORT_SERVICE_NAME} -o  yaml  > ${TEMP_CANARY_SERVICE_FILE}
    yq w --inplace --doc  0 ${TEMP_CANARY_SERVICE_FILE}  metadata.labels.deployment stop
    kubectl apply -f ${TEMP_CANARY_SERVICE_FILE} 
    echo "updated canary service with deployment: stop label"
    sleep $STEP_INTERVAL
else 
    echo "Canary Deployment not found....."
fi

if  kubectl get ing | grep  ${CANARY_INGRESS_NAME};
then
    echo "Removing the canary deployment....."
    kubectl delete -f ${CANARY_DEPLOYMENT_FILE}
else 
    echo "Canary Deployment not found....."
fi
