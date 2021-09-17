#!/bin/bash

#### This script will be executed only after deployment is successfull and acceptance test is passed.
#### Switch the ingress controller to new environment.

#### Check if the prod ingress controller is running.
#### If not, Then this is the first deployment of the application.
#### Deploy the ingress controller by pointing to blue environment.

source ./pipeline.data
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}
function change_ingress(){

    echo $INGRESS_NAME
    echo $CURRENT_DEPLOYMENT_SERVICE
    if  kubectl get ing | grep  ${INGRESS_NAME};
    then
        echo "Updating Ingress ${INGRESS_NAME} to point to Deployment ${CURRENT_DEPLOYMENT_SERVICE}."
        kubectl get ing ${INGRESS_NAME} -o json | jq  --arg serviceName "${CURRENT_DEPLOYMENT_SERVICE}"  '.spec.rules[0].http.paths[0].backend.service.name = $serviceName' > temp.json
        kubectl apply -f temp.json
    else 
        sed -i "s/${CIP_SERVICE_NAME}/${BLUE_CIP_SERVICE_NAME}/g" ${PROD_INGRESS_FILE}
        kubectl apply -f ${PROD_INGRESS_FILE}
    fi

    echo "Ingress controller has been updated."
}

function change_nodeport(){
    echo $CURRENT_DEPLOYMENT_SERVICE

    if  kubectl get svc | grep  ${NODEPORT_SERVICE_NAME};
    then
        echo "Updating NodePort ${NODEPORT_SERVICE_NAME} to point to Deployment ${CURRENT_DEPLOYMENT_SERVICE}."
        kubectl get svc ${NODEPORT_SERVICE_NAME}  -o json | jq  --arg serviceName "${CURRENT_DEPLOYMENT_APP}"  '.spec.selector.app = $serviceName' > temp.json
        kubectl apply -f temp.json
    else 
        sed -i "s/${DEPLOYMENT_NAME}/${BLUE_DEPLOYMENT_NAME}/g" ${PROD_NODEPORT_SERVICE_FILE}
        kubectl apply -f ${PROD_NODEPORT_SERVICE_FILE}
    fi

    echo "Nodeport has been updated."
    
}



if [ ! -z "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; 
then
  echo "Deployment Cluster belongs to 'Standard' Plan. Begin update of Ingress."
  change_ingress
else 
  echo "Deployment Cluster belongs to 'Lite' Plan. Begin update of NodePort."
  change_nodeport
fi
