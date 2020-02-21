#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/cluster_bind_service.sh) and 'source' it from your pipeline job
#    source ./scripts/cluster_bind_service.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cluster_bind_service.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cluster_bind_service.sh

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

echo "SERVICE_ID=${SERVICE_ID}"

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

BINDING=$( ibmcloud ks cluster services -n $CLUSTER_NAMESPACE --cluster  $PIPELINE_KUBERNETES_CLUSTER_NAME | grep $SERVICE_ID ||:)
if [ -z "$BINDING" ]; then
  ibmcloud ks cluster service bind --cluster $PIPELINE_KUBERNETES_CLUSTER_NAME --namespace $CLUSTER_NAMESPACE --service $SERVICE_ID
else
  echo "Service already bound in cluster namespace"
fi