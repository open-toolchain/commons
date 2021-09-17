#!/bin/bash

#### This script will be executed only after deployment is successful and acceptance tests have passed.
#### update the Old Deployment with Canary Deployment.

#### Check if the prod ingress controller is running.
#### If not, Then this is the first deployment of the application.
#### Deploy the ingress controller by pointing to blue environment.

source ./pipeline.data
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}

function update_prod(){

    echo $INGRESS_NAME
    export CURRENT_DEPLOYMENT_SERVICE 
    if  kubectl get ing | grep  ${CANARY_INGRESS_NAME};
    then
       echo "updating the prod deployment..."
       kubectl apply -f ${DEPLOYMENT_FILE}
       sleep 10
       echo "Deleting Canary deployment..."
       kubectl delete -f ${CANARY_DEPLOYMENT_FILE}
       sleep 10
    else 
        echo "This is the first deployment of this application."
    fi

    echo "Prod deployment has been updated."
}


update_prod
