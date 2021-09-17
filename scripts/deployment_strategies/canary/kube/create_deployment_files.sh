#!/bin/bash

echo "DEPLOYMENT_FILE is $DEPLOYMENT_FILE"


  ## Canary Deployment files.
  CANARY_DEPLOYMENT_FILE=canary.yaml

  # Get the deployment metadata names.
  DEPLOYMENT_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE} --tojson  | jq -r '.[] | select(.kind == "Deployment").metadata.name')
  NODEPORT_SERVICE_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Service" and .spec.type == "NodePort").metadata.name')
  CIP_SERVICE_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Service" and .spec.type == "ClusterIP").metadata.name')
  INGRESS_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Ingress").metadata.name')

  # Set the  CANARY deployment names.

  CANARY_DEPLOYMENT_NAME=${DEPLOYMENT_NAME}-canary
  CANARY_NODEPORT_SERVICE_NAME=${NODEPORT_SERVICE_NAME}-canary
  CANARY_CIP_SERVICE_NAME=${CIP_SERVICE_NAME}-canary
  CANARY_INGRESS_NAME=${INGRESS_NAME}-canary

  cp ${DEPLOYMENT_FILE} ${CANARY_DEPLOYMENT_FILE}

  INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson ${DEPLOYMENT_FILE} | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
  if [ -z "$INGRESS_DOC_INDEX" ]; then
    echo "No Kubernetes Ingress definition found in $DEPLOYMENT_FILE."
    exit 1
  fi
  

  sed -i "s/${DEPLOYMENT_NAME}$/${CANARY_DEPLOYMENT_NAME}/g" ${CANARY_DEPLOYMENT_FILE}
  sed -i "s/${NODEPORT_SERVICE_NAME}$/${CANARY_NODEPORT_SERVICE_NAME}/g" ${CANARY_DEPLOYMENT_FILE}
  sed -i "s/${CIP_SERVICE_NAME}$/${CANARY_CIP_SERVICE_NAME}/g" ${CANARY_DEPLOYMENT_FILE}
  sed -i "s/${INGRESS_NAME}$/${CANARY_INGRESS_NAME}/g" ${CANARY_DEPLOYMENT_FILE}

  # Update Canary deployment with weights.
  yq w --inplace --doc  $INGRESS_DOC_INDEX $CANARY_DEPLOYMENT_FILE metadata.annotations.[nginx.ingress.kubernetes.io/canary] \"true\"
  yq w --inplace --doc  $INGRESS_DOC_INDEX $CANARY_DEPLOYMENT_FILE metadata.annotations.[nginx.ingress.kubernetes.io/canary-weight] \"0\"




  pipeline_data="pipeline.data"
  {
    echo "export DEPLOYMENT_FILE=\"${DEPLOYMENT_FILE}\""
    echo "export CANARY_DEPLOYMENT_FILE=\"${CANARY_DEPLOYMENT_FILE}\""
    echo "export CANARY_DEPLOYMENT_NAME=\"${CANARY_DEPLOYMENT_NAME}\""
    echo "export CANARY_CIP_SERVICE_NAME=\"${CANARY_CIP_SERVICE_NAME}\""
    echo "export CANARY_INGRESS_NAME=\"${CANARY_INGRESS_NAME}\""
    echo "export DEPLOYMENT_NAME=\"${DEPLOYMENT_NAME}\""
    echo "export NODEPORT_SERVICE_NAME=\"${NODEPORT_SERVICE_NAME}\""
    echo "export CIP_SERVICE_NAME=\"${CIP_SERVICE_NAME}\""
    echo "export INGRESS_NAME=\"${INGRESS_NAME}\""
    echo "export CANARY_NODEPORT_SERVICE_NAME=\"${CANARY_NODEPORT_SERVICE_NAME}\""
  } >> "$pipeline_data"

  chmod 777 "$pipeline_data"






