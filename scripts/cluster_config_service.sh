#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/cluster_config_service.sh) and 'source' it from your pipeline job
#    source ./scripts/cluster_config_service.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cluster_config_service.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cluster_config_service.sh

# This script does bind a given IBM Cloud Service identified by its SERVICE_ID to a cluster (via secret).
# This script should be executed in a Kubernetes deploy job.

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties | grep -v -i password
else 
  echo "build.properties : not found"
fi 
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://cloud.ibm.com/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

export SERVICE_LOCATION=${SERVICE_LOCATION:-$IBM_CLOUD_REGION}
export SERVICE_IAM_ROLE=${SERVICE_IAM_ROLE:-"Manager"}

echo "INSTANCE_NAME=${INSTANCE_NAME}"
echo "SERVICE_NAME=${SERVICE_NAME}"
echo "SERVICE_PLAN=${SERVICE_PLAN}"
echo "SERVICE_LOCATION=${SERVICE_LOCATION}"
echo "SERVICE_IAM_ROLE=${SERVICE_IAM_ROLE}"
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

# Create service (if needed)
SERVICE=$(ibmcloud resource service-instances | grep ${INSTANCE_NAME} ||:)
if [ -z "$SERVICE" ]; then
  ibmcloud resource service-instance-create --parameters '{"legacyCredentials": true}' ${INSTANCE_NAME} ${SERVICE_NAME} ${SERVICE_PLAN} ${SERVICE_LOCATION}
else
  echo -e "Keeping existing service: ${INSTANCE_NAME}"
fi
# Bind service to cluster
SERVICE_ID=$(ibmcloud resource service-instance ${INSTANCE_NAME} --output json | jq -r '.[0].guid')
BINDING=$( ibmcloud ks cluster services -n $CLUSTER_NAMESPACE $PIPELINE_KUBERNETES_CLUSTER_NAME | grep $SERVICE_ID ||:)
if [ -z "$BINDING" ]; then
  ibmcloud ks cluster service bind --cluster $PIPELINE_KUBERNETES_CLUSTER_NAME \
    --namespace $CLUSTER_NAMESPACE --service $SERVICE_ID --role $SERVICE_IAM_ROLE
else
  echo -e "Service already bound in cluster namespace: ${CLUSTER_NAMESPACE}"
fi
