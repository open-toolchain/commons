#!/bin/bash

#### This script will be executed only after deployment is successfull and acceptance test is passed.
#### Switch the ingress controller to new environment.

#### Check if the prod ingress controller is running.
#### If not, Then this is the first deployment of the application.
#### Deploy the ingress controller by pointing to blue environment.

source ./pipeline.data
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}
function switch_ingress(){

    echo $INGRESS_NAME
    export CURRENT_DEPLOYMENT_SERVICE 
    if  kubectl get ing | grep  ${INGRESS_NAME};
    then
        CURRENT_SERVICE=$(kubectl get ing ${INGRESS_NAME} -o json | jq -r .spec.rules[0].http.paths[0].backend.service.name)
        if [ "${CURRENT_SERVICE}" = "${BLUE_CIP_SERVICE_NAME}" ];
        then
            echo "Existing service is Blue. Begin switch to green service."
            CURRENT_DEPLOYMENT_SERVICE=${GREEN_CIP_SERVICE_NAME}
        elif [ "${CURRENT_SERVICE}" = "${GREEN_CIP_SERVICE_NAME}" ];
        then 
            echo "Existing service is Green. Begin switch to blue service."
            CURRENT_DEPLOYMENT_SERVICE=${BLUE_CIP_SERVICE_NAME}
        else 
            echo "unable to recognize the current service pointed by ingress controller."  
            exit 1
        fi
        echo "Updating Ingress to point to ${CURRENT_DEPLOYMENT_SERVICE} deployment."
        kubectl get ing ${INGRESS_NAME} -o json | jq  --arg serviceName "${CURRENT_DEPLOYMENT_SERVICE}"  '.spec.rules[0].http.paths[0].backend.service.name = $serviceName' > temp.json
        kubectl apply -f temp.json

        ACCEPTANCE_TEST_URL=$(kubectl get ing | grep ${INGRESS_NAME} | awk {'print $3'})
        pipeline_data="pipeline.data"
        {
        echo "export ACCEPTANCE_TEST_URL=\"${ACCEPTANCE_TEST_URL}\""
        } >> "$pipeline_data"
    else 
        echo "There is no active deployment of the application."
        exit 1
    fi

    echo "Ingress controller has been updated."
}

function switch_nodeport(){
    export CURRENT_DEPLOYMENT_APP

    if  kubectl get svc | grep  ${NODEPORT_SERVICE_NAME};
    then
        CURRENT_SERVICE=$(kubectl get svc ${NODEPORT_SERVICE_NAME} -o json | jq -r .spec.selector.app)
        if [ "${CURRENT_SERVICE}" = "${BLUE_DEPLOYMENT_NAME}" ];
        then
            echo "Existing service is Blue. Begin switch to green service."
            CURRENT_DEPLOYMENT_APP=${GREEN_DEPLOYMENT_NAME}
        elif [ "${CURRENT_SERVICE}" = "${GREEN_DEPLOYMENT_NAME}" ];
        then 
            echo "Existing service is Green. Begin switch to blue service."
            CURRENT_DEPLOYMENT_APP=${BLUE_DEPLOYMENT_NAME}
        else 
            echo "unable to recognize the current service pointed by ingress controller."  
        fi

        echo "Updating Ingress to point to ${CURRENT_DEPLOYMENT_SERVICE} deployment."
        kubectl get svc ${NODEPORT_SERVICE_NAME}  -o json | jq  --arg serviceName "${CURRENT_DEPLOYMENT_APP}"  '.spec.selector.app = $serviceName' > temp.json
        kubectl apply -f temp.json
        IP_ADDR=$( ibmcloud ks workers --cluster ${CLUSTER_ID} | grep normal | head -n 1 | awk '{ print $2 }' )
        PORT=$( kubectl get service ${NODEPORT_SERVICE_NAME} --namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.spec.ports[0].nodePort' )
        ACCEPTANCE_TEST_URL=http://${IP_ADDR}:${PORT}
        
        pipeline_data="pipeline.data"
        {
        echo "export ACCEPTANCE_TEST_URL=\"${ACCEPTANCE_TEST_URL}\""
        } >> "$pipeline_data"

    else 
        echo "There is no active deployment of the application."
        exit 1
    fi

    
    
}



if [ ! -z "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; 
then
  echo "Deployment Cluster belongs to 'Standard' Plan. Begin update of Ingress."
  switch_ingress
else 
  echo "Deployment Cluster belongs to 'Lite' Plan. Begin update of NodePort."
  switch_nodeport
fi
