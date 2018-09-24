#!/bin/bash
# uncomment to debug the script
#set -x
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
  cat build.properties
else 
  echo "build.properties : not found"
fi 
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

echo "INSTANCE_NAME=${INSTANCE_NAME}"
echo "SERVICE_NAME=${SERVICE_NAME}"
echo "SERVICE_PLAN=${SERVICE_PLAN}"
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

# Create service (if needed)
SERVICE=$(bx resource service-instances | grep ${INSTANCE_NAME} ||:)
if [ -z "$SERVICE" ]; then
  echo -e "Keeping existing service: ${INSTANCE_NAME}"
else
  bx resource service-instance-create ${INSTANCE_NAME} ${SERVICE_NAME} ${STAGING_REGION_ID}
fi
# Bind service to cluster
SERVICE_ID=$(bx resource service-instance ${INSTANCE_NAME} --output json | jq -r '.[0].guid')
BINDING=$( bx cs cluster-services -n $CLUSTER_NAMESPACE $PIPELINE_KUBERNETES_CLUSTER_NAME | grep $SERVICE_ID ||:)
if [ -z "$BINDING" ]; then
  bx cs cluster-service-bind $PIPELINE_KUBERNETES_CLUSTER_NAME $CLUSTER_NAMESPACE $SERVICE_ID
else
  echo -e "Service already bound in cluster namespace: ${CLUSTER_NAMESPACE}"
fi