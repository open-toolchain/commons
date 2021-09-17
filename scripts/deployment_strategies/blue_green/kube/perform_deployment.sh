#!/bin/bash

#### Prepare all the deployment files.
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}


#### Source all the env variables.
source ./pipeline.data

function perform_ingress_deployment() {

    CURRENT_DEPLOYMENT_FILE=$1
    CURRENT_DEPLOYMENT_SERVICE_FILE=$2
    CURRENT_DEPLOYMENT_SERVICE=$3
    CURRENT_INGRESS_FILE=$4
    CURRENT_INGRESS_NAME=$5

    echo "Performing  deployment.."
    #### Deploy the blue deployment.
    #### Point the ingress controller to blue deployment.

    echo "Apply deployment using manifest ${CURRENT_DEPLOYMENT_FILE}"
    kubectl apply -f ${CURRENT_DEPLOYMENT_FILE} 


    echo "Apply service using manifest ${CURRENT_DEPLOYMENT_SERVICE_FILE}"
    kubectl apply -f ${CURRENT_DEPLOYMENT_SERVICE_FILE} 

    echo "Apply ingress using manifest ${CURRENT_INGRESS_FILE}"
    kubectl apply -f ${CURRENT_INGRESS_FILE} 

    ACCEPTANCE_TEST_URL=$(kubectl get ing | grep ${CURRENT_INGRESS_NAME} | awk {'print $3'})


    pipeline_data="pipeline.data"
    {
    echo "export ACCEPTANCE_TEST_URL=\"${ACCEPTANCE_TEST_URL}\""
    echo "export CURRENT_DEPLOYMENT_SERVICE=\"${CURRENT_DEPLOYMENT_SERVICE}\""
    } >> "$pipeline_data"

}

function perform_nodeport_deployment() {

    CURRENT_DEPLOYMENT_FILE=$1
    CURRENT_DEPLOYMENT_SERVICE_FILE=$2
    CURRENT_DEPLOYMENT_APP=$3
    CURRENT_DEPLOYMENT_SERVICE=$4
  

    echo "Performing  deployment.."
    #### Deploy the blue deployment.
    #### Point the ingress controller to blue deployment.

    echo "Apply deployment using manifest ${CURRENT_DEPLOYMENT_FILE}"
    kubectl apply -f ${CURRENT_DEPLOYMENT_FILE} 


    echo "Apply service using manifest ${CURRENT_DEPLOYMENT_SERVICE_FILE}"
    kubectl apply -f ${CURRENT_DEPLOYMENT_SERVICE_FILE} 

    IP_ADDR=$( ibmcloud ks workers --cluster ${CLUSTER_ID} | grep normal | head -n 1 | awk '{ print $2 }' )
    PORT=$( kubectl get service ${CURRENT_DEPLOYMENT_SERVICE} --namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.spec.ports[0].nodePort' )

    ACCEPTANCE_TEST_URL=http://${IP_ADDR}:${PORT}


    pipeline_data="pipeline.data"
    {
    echo "export ACCEPTANCE_TEST_URL=\"${ACCEPTANCE_TEST_URL}\""
    echo "export CURRENT_DEPLOYMENT_APP=\"${CURRENT_DEPLOYMENT_APP}\""
    } >> "$pipeline_data"

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
        
        CURRENT_SERVICE=$(kubectl get ing ${INGRESS_NAME} -o json | jq -r .spec.rules[0].http.paths[0].backend.service.name)
        if [ "${CURRENT_SERVICE}" = "${BLUE_CIP_SERVICE_NAME}" ];
        then
            echo "Existing service is Blue. Begin deployment of Green service."
            perform_ingress_deployment ${GREEN_DEPLOYMENT_FILE} ${GREEN_CIP_DEPLOYMENT_FILE} ${GREEN_CIP_SERVICE_NAME} ${GREEN_INGRESS_DEPLOYMENT_FILE} ${GREEN_INGRESS_NAME}
        elif [ "${CURRENT_SERVICE}" = "${GREEN_CIP_SERVICE_NAME}" ];
        then 
            echo "Existing service is Green. Begin deployment of Blue service."
            perform_ingress_deployment ${BLUE_DEPLOYMENT_FILE} ${BLUE_CIP_DEPLOYMENT_FILE} ${BLUE_CIP_SERVICE_NAME} ${BLUE_INGRESS_DEPLOYMENT_FILE} ${BLUE_INGRESS_NAME}
        else 
            echo "Unable to find existing service. Begin deployment of Blue service."
        fi
        
    else 
        perform_ingress_deployment ${BLUE_DEPLOYMENT_FILE} ${BLUE_CIP_DEPLOYMENT_FILE} ${BLUE_CIP_SERVICE_NAME} ${BLUE_INGRESS_DEPLOYMENT_FILE} ${BLUE_INGRESS_NAME}
    fi

}



#### Check if prod ingress controller running on the cluster.
#### If there are no ingress contoroller running on the cluster,
#### then this is the first deployment of the application.
#### Deploy the  application as blue deployment.
#### Point the prod ingreess contoller to blue deployment.
#### 
#### If there is an ingress controller already. 
#### Then check where ingress controller is pointing.
function nodeport_deployment() {

    if  kubectl get svc | grep  ${NODEPORT_SERVICE_NAME};
    then
        
        CURRENT_SERVICE=$(kubectl get svc ${NODEPORT_SERVICE_NAME} -o json | jq -r .spec.selector.app)
        if [ "${CURRENT_SERVICE}" = "${BLUE_DEPLOYMENT_NAME}" ];
        then
            echo "Existing service is Blue. Begin deployment of Green service."
            perform_nodeport_deployment ${GREEN_DEPLOYMENT_FILE} ${GREEN_NODEPORT_DEPLOYMENT_FILE} ${GREEN_DEPLOYMENT_NAME} ${BLUE_NODEPORT_SERVICE_NAME}
        elif [ "${CURRENT_SERVICE}" = "${GREEN_DEPLOYMENT_NAME}" ];
        then 
           echo "Existing service is Green. Begin deployment of Blue service."
            perform_nodeport_deployment ${BLUE_DEPLOYMENT_FILE} ${BLUE_NODEPORT_DEPLOYMENT_FILE} ${BLUE_DEPLOYMENT_NAME} ${GREEN_NODEPORT_SERVICE_NAME}
        else 
           echo "Unable to find existing service. Begin deployment of Blue service."  
        fi
        
    else 
        perform_nodeport_deployment ${BLUE_DEPLOYMENT_FILE} ${BLUE_NODEPORT_DEPLOYMENT_FILE} ${BLUE_DEPLOYMENT_NAME} ${BLUE_NODEPORT_SERVICE_NAME}
    fi

}




if [ ! -z "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; 
then
  echo "Deployment Cluster belongs to 'Standard' Plan. Begin update of Ingress."
  ingress_deployment
else 
  echo "Deployment Cluster belongs to 'Lite' Plan. Begin update of NodePort."
  nodeport_deployment
fi