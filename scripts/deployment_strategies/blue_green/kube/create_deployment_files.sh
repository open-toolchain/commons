#!/bin/bash

echo "DEPLOYMENT_FILE is $DEPLOYMENT_FILE"

#### Function created deployment files needed for ingress controller.
#### This will be used if cluster is on paid plan.
function create_blue_green_deployment_manifests() {


  PROD_INGRESS_FILE=prod_ingress_file.yaml


  ## Green Deployment files.
  GREEN_DEPLOYMENT_FILE=green.yaml
  TEMP_GREEN_DEPLOYMENT_FILE=temp_green.yaml
  GREEN_NODEPORT_DEPLOYMENT_FILE=green_node_port.yaml
  GREEN_CIP_DEPLOYMENT_FILE=green_cip.yaml
  GREEN_INGRESS_DEPLOYMENT_FILE=green_ingress.yaml


  ## blue Deployment files.
  BLUE_DEPLOYMENT_FILE=blue.yaml
  TEMP_BLUE_DEPLOYMENT_FILE=temp_blue.yaml
  BLUE_NODEPORT_DEPLOYMENT_FILE=blue_node_port.yaml
  BLUE_CIP_DEPLOYMENT_FILE=blue_cip.yaml
  BLUE_INGRESS_DEPLOYMENT_FILE=blue_ingress.yaml


  # Get the deployment metadata names.
  DEPLOYMENT_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE} --tojson  | jq -r '.[] | select(.kind == "Deployment").metadata.name')
  NODEPORT_SERVICE_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Service" and .spec.type == "NodePort").metadata.name')
  CIP_SERVICE_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Service" and .spec.type == "ClusterIP").metadata.name')
  INGRESS_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Ingress").metadata.name')

  # Set the green deployment names.

  GREEN_DEPLOYMENT_NAME=${DEPLOYMENT_NAME}-green
  GREEN_NODEPORT_SERVICE_NAME=${NODEPORT_SERVICE_NAME}-green
  GREEN_CIP_SERVICE_NAME=${CIP_SERVICE_NAME}-green
  GREEN_INGRESS_NAME=temp-ingress


  # Set the blue deployment names.

  BLUE_DEPLOYMENT_NAME=${DEPLOYMENT_NAME}-blue
  BLUE_NODEPORT_SERVICE_NAME=${NODEPORT_SERVICE_NAME}-blue
  BLUE_CIP_SERVICE_NAME=${CIP_SERVICE_NAME}-blue
  BLUE_INGRESS_NAME=temp-ingress

  cp ${DEPLOYMENT_FILE} ${TEMP_BLUE_DEPLOYMENT_FILE}
  cp ${DEPLOYMENT_FILE} ${TEMP_GREEN_DEPLOYMENT_FILE}



  sed -i "s/${DEPLOYMENT_NAME}/${GREEN_DEPLOYMENT_NAME}/g" ${TEMP_GREEN_DEPLOYMENT_FILE}
  sed -i "s/${NODEPORT_SERVICE_NAME}$/${GREEN_NODEPORT_SERVICE_NAME}/g" ${TEMP_GREEN_DEPLOYMENT_FILE}
  sed -i "s/${CIP_SERVICE_NAME}$/${GREEN_CIP_SERVICE_NAME}/g" ${TEMP_GREEN_DEPLOYMENT_FILE}
  sed -i "s/${INGRESS_NAME}$/${GREEN_INGRESS_NAME}/g" ${TEMP_GREEN_DEPLOYMENT_FILE}

  sed -i "s/${DEPLOYMENT_NAME}/${BLUE_DEPLOYMENT_NAME}/g" ${TEMP_BLUE_DEPLOYMENT_FILE}
  sed -i "s/${NODEPORT_SERVICE_NAME}$/${BLUE_NODEPORT_SERVICE_NAME}/g" ${TEMP_BLUE_DEPLOYMENT_FILE}
  sed -i "s/${CIP_SERVICE_NAME}$/${BLUE_CIP_SERVICE_NAME}/g" ${TEMP_BLUE_DEPLOYMENT_FILE}
  sed -i "s/${INGRESS_NAME}$/${BLUE_INGRESS_NAME}/g" ${TEMP_BLUE_DEPLOYMENT_FILE}


  yq r --doc 0 ${TEMP_BLUE_DEPLOYMENT_FILE}  >> ${BLUE_DEPLOYMENT_FILE} 
  yq r --doc 1 ${TEMP_BLUE_DEPLOYMENT_FILE}  >> ${BLUE_NODEPORT_DEPLOYMENT_FILE} 
  yq r --doc 2 ${TEMP_BLUE_DEPLOYMENT_FILE}  >> ${BLUE_CIP_DEPLOYMENT_FILE} 
  yq r --doc 3 ${TEMP_BLUE_DEPLOYMENT_FILE}  >> ${BLUE_INGRESS_DEPLOYMENT_FILE} 


  yq r --doc 0 ${TEMP_GREEN_DEPLOYMENT_FILE}  >> ${GREEN_DEPLOYMENT_FILE}
  yq r --doc 1 ${TEMP_GREEN_DEPLOYMENT_FILE}  >> ${GREEN_NODEPORT_DEPLOYMENT_FILE}
  yq r --doc 2 ${TEMP_GREEN_DEPLOYMENT_FILE}  >> ${GREEN_CIP_DEPLOYMENT_FILE}
  yq r --doc 3 ${TEMP_GREEN_DEPLOYMENT_FILE}  >> ${GREEN_INGRESS_DEPLOYMENT_FILE}

  yq r  --doc "3" ${DEPLOYMENT_FILE}  >> ${PROD_INGRESS_FILE}


  pipeline_data="pipeline.data"
  {
    echo "export DEPLOYMENT_FILE=\"${DEPLOYMENT_FILE}\""
    echo "export GREEN_DEPLOYMENT_FILE=\"${GREEN_DEPLOYMENT_FILE}\""
    echo "export TEMP_GREEN_DEPLOYMENT_FILE=\"${TEMP_GREEN_DEPLOYMENT_FILE}\""
    echo "export GREEN_NODEPORT_DEPLOYMENT_FILE=\"${GREEN_NODEPORT_DEPLOYMENT_FILE}\""
    echo "export GREEN_CIP_DEPLOYMENT_FILE=\"${GREEN_CIP_DEPLOYMENT_FILE}\""
    echo "export GREEN_INGRESS_DEPLOYMENT_FILE=\"${GREEN_INGRESS_DEPLOYMENT_FILE}\""
    echo "export BLUE_DEPLOYMENT_FILE=\"${BLUE_DEPLOYMENT_FILE}\""
    echo "export TEMP_BLUE_DEPLOYMENT_FILE=\"${TEMP_BLUE_DEPLOYMENT_FILE}\""
    echo "export BLUE_NODEPORT_DEPLOYMENT_FILE=\"${BLUE_NODEPORT_DEPLOYMENT_FILE}\""
    echo "export BLUE_CIP_DEPLOYMENT_FILE=\"${BLUE_CIP_DEPLOYMENT_FILE}\""
    echo "export BLUE_INGRESS_DEPLOYMENT_FILE=\"${BLUE_INGRESS_DEPLOYMENT_FILE}\""
    echo "export DEPLOYMENT_NAME=\"${DEPLOYMENT_NAME}\""
    echo "export NODEPORT_SERVICE_NAME=\"${NODEPORT_SERVICE_NAME}\""
    echo "export CIP_SERVICE_NAME=\"${CIP_SERVICE_NAME}\""
    echo "export INGRESS_NAME=\"${INGRESS_NAME}\""
    echo "export GREEN_DEPLOYMENT_NAME=\"${GREEN_DEPLOYMENT_NAME}\""
    echo "export GREEN_NODEPORT_SERVICE_NAME=\"${GREEN_NODEPORT_SERVICE_NAME}\""
    echo "export GREEN_CIP_SERVICE_NAME=\"${GREEN_CIP_SERVICE_NAME}\""
    echo "export GREEN_INGRESS_NAME=\"${GREEN_INGRESS_NAME}\""
    echo "export BLUE_DEPLOYMENT_NAME=\"${BLUE_DEPLOYMENT_NAME}\""
    echo "export BLUE_NODEPORT_SERVICE_NAME=\"${BLUE_NODEPORT_SERVICE_NAME}\""
    echo "export BLUE_CIP_SERVICE_NAME=\"${BLUE_CIP_SERVICE_NAME}\""
    echo "export BLUE_INGRESS_NAME=\"${BLUE_INGRESS_NAME}\""
    echo "export PROD_INGRESS_FILE=\"${PROD_INGRESS_FILE}\""
    echo "export PROD_NODEPORT_SERVICE_FILE=\"${PROD_NODEPORT_SERVICE_FILE}\""
    echo "export CLUSTER_INGRESS_SUBDOMAIN=\"${CLUSTER_INGRESS_SUBDOMAIN}\""
    echo "export KEEP_INGRESS_CUSTOM_DOMAIN=\"${KEEP_INGRESS_CUSTOM_DOMAIN}\""
  } >> "$pipeline_data"

  chmod 777 "$pipeline_data"


}

#### Function created deployment files needed for Nodeport service.
#### This will be used if cluster is on free plan.
function create_blue_green_service_manifests() {


  PROD_NODEPORT_SERVICE_FILE=prod_node_port_file.yaml

  ## Green Deployment files.
  GREEN_DEPLOYMENT_FILE=green.yaml
  TEMP_GREEN_DEPLOYMENT_FILE=temp_green.yaml
  GREEN_NODEPORT_DEPLOYMENT_FILE=green_node_port.yaml

  ## blue Deployment files.
  BLUE_DEPLOYMENT_FILE=blue.yaml
  TEMP_BLUE_DEPLOYMENT_FILE=temp_blue.yaml
  BLUE_NODEPORT_DEPLOYMENT_FILE=blue_node_port.yaml
  
  # Get the deployment metadata names.
  DEPLOYMENT_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE} --tojson  | jq -r '.[] | select(.kind == "Deployment").metadata.name')
  NODEPORT_SERVICE_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Service" and .spec.type == "NodePort").metadata.name')

  # Set the green deployment names.

  GREEN_DEPLOYMENT_NAME=${DEPLOYMENT_NAME}-green
  GREEN_NODEPORT_SERVICE_NAME=temp-nodeport

  # Set the blue deployment names.

  BLUE_DEPLOYMENT_NAME=${DEPLOYMENT_NAME}-blue
  BLUE_NODEPORT_SERVICE_NAME=temp-nodeport

  cp ${DEPLOYMENT_FILE} ${TEMP_BLUE_DEPLOYMENT_FILE}
  cp ${DEPLOYMENT_FILE} ${TEMP_GREEN_DEPLOYMENT_FILE}


  sed -i "s/${DEPLOYMENT_NAME}/${GREEN_DEPLOYMENT_NAME}/g" ${TEMP_GREEN_DEPLOYMENT_FILE}
  sed -i "s/${NODEPORT_SERVICE_NAME}$/${GREEN_NODEPORT_SERVICE_NAME}/g" ${TEMP_GREEN_DEPLOYMENT_FILE}
  
  sed -i "s/${DEPLOYMENT_NAME}/${BLUE_DEPLOYMENT_NAME}/g" ${TEMP_BLUE_DEPLOYMENT_FILE}
  sed -i "s/${NODEPORT_SERVICE_NAME}$/${BLUE_NODEPORT_SERVICE_NAME}/g" ${TEMP_BLUE_DEPLOYMENT_FILE}
  

  yq r --doc 0 ${TEMP_BLUE_DEPLOYMENT_FILE}  >> ${BLUE_DEPLOYMENT_FILE} 
  yq r --doc 1 ${TEMP_BLUE_DEPLOYMENT_FILE}  >> ${BLUE_NODEPORT_DEPLOYMENT_FILE} 

  yq r --doc 0 ${TEMP_GREEN_DEPLOYMENT_FILE}  >> ${GREEN_DEPLOYMENT_FILE}
  yq r --doc 1 ${TEMP_GREEN_DEPLOYMENT_FILE}  >> ${GREEN_NODEPORT_DEPLOYMENT_FILE}

  yq r  --doc "1" ${DEPLOYMENT_FILE}  >> ${PROD_NODEPORT_SERVICE_FILE}


  pipeline_data="pipeline.data"
  {
    echo "export DEPLOYMENT_FILE=\"${DEPLOYMENT_FILE}\""
    echo "export GREEN_DEPLOYMENT_FILE=\"${GREEN_DEPLOYMENT_FILE}\""
    echo "export TEMP_GREEN_DEPLOYMENT_FILE=\"${TEMP_GREEN_DEPLOYMENT_FILE}\""
    echo "export GREEN_NODEPORT_DEPLOYMENT_FILE=\"${GREEN_NODEPORT_DEPLOYMENT_FILE}\""
    echo "export BLUE_DEPLOYMENT_FILE=\"${BLUE_DEPLOYMENT_FILE}\""
    echo "export TEMP_BLUE_DEPLOYMENT_FILE=\"${TEMP_BLUE_DEPLOYMENT_FILE}\""
    echo "export BLUE_NODEPORT_DEPLOYMENT_FILE=\"${BLUE_NODEPORT_DEPLOYMENT_FILE}\""
    echo "export DEPLOYMENT_NAME=\"${DEPLOYMENT_NAME}\""
    echo "export NODEPORT_SERVICE_NAME=\"${NODEPORT_SERVICE_NAME}\""
    echo "export GREEN_DEPLOYMENT_NAME=\"${GREEN_DEPLOYMENT_NAME}\""
    echo "export GREEN_NODEPORT_SERVICE_NAME=\"${GREEN_NODEPORT_SERVICE_NAME}\""
    echo "export BLUE_DEPLOYMENT_NAME=\"${BLUE_DEPLOYMENT_NAME}\""
    echo "export BLUE_NODEPORT_SERVICE_NAME=\"${BLUE_NODEPORT_SERVICE_NAME}\""
    echo "export PROD_NODEPORT_SERVICE_FILE=\"${PROD_NODEPORT_SERVICE_FILE}\""
    echo "export CLUSTER_INGRESS_SUBDOMAIN=\"${CLUSTER_INGRESS_SUBDOMAIN}\""
    echo "export KEEP_INGRESS_CUSTOM_DOMAIN=\"${KEEP_INGRESS_CUSTOM_DOMAIN}\""
    echo "export CLUSTER_ID=\"${CLUSTER_ID}\""
  } >> "$pipeline_data"

  chmod 777 "$pipeline_data"


}


if [ ! -z "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; 
then
  create_blue_green_deployment_manifests
else 
  create_blue_green_service_manifests
fi
