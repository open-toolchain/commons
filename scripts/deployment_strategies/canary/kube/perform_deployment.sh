#!/bin/bash

#### Prepare all the deployment files.
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}


#### Source all the env variables.
source ./pipeline.data

function perform_ingress_deployment() {

    CURRENT_DEPLOYMENT_FILE=$1
    CURRENT_INGRESS_NAME=$2

    echo "Performing  deployment.."
    #### Deploy the blue deployment.
    #### Point the ingress controller to blue deployment.

    echo "Deploying application.. ${CURRENT_DEPLOYMENT_FILE}"
    kubectl apply -f ${CURRENT_DEPLOYMENT_FILE} 

    ACCEPTANCE_TEST_URL=$(kubectl get ing | grep ${CURRENT_INGRESS_NAME} | awk {'print $3'})


    pipeline_data="pipeline.data"
    {
    echo "export ACCEPTANCE_TEST_URL=\"${ACCEPTANCE_TEST_URL}\""
    } >> "$pipeline_data"


    echo "Done deployment...."
}




#### Check if prod ingress controller running on the cluster.
#### If there are no ingress contoroller running on the cluster,
#### then this is the first deployment of the application.
#### Deploy the  application as blue deployment.
#### Point the prod ingreess contoller to blue deployment.
#### 
#### If there is an ingress controller already. 
#### Then check where ingress controller is pointing.
function ingress_deployment() {

    if  kubectl get ing | grep  ${INGRESS_NAME};
    then
        perform_ingress_deployment ${CANARY_DEPLOYMENT_FILE} ${CANARY_INGRESS_NAME}
        
    else 
        perform_ingress_deployment ${DEPLOYMENT_FILE} ${INGRESS_NAME}
    fi

}

ingress_deployment




