#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_kubectl.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_kubectl.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_kubectl.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_kubectl.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "REGISTRY_TOKEN=${REGISTRY_TOKEN}"
#View build properties
# cat build.properties
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

echo "=========================================================="
#Check cluster availability
IP_ADDR=$( bx cs workers $PIPELINE_KUBERNETES_CLUSTER_NAME | grep normal | head -n 1 | awk '{ print $2 }' )
if [ -z "$IP_ADDR" ]; then
  echo "$PIPELINE_KUBERNETES_CLUSTER_NAME not created or workers not ready"
  exit 1
fi
#Connect to a different container-service api by uncommenting and specifying an api endpoint
#bx cs init --host https://us-south.containers.bluemix.net
echo ""
echo "DEPLOYING USING MANIFEST:"
cat deployment.yml
kubectl apply -f deployment.yml  
echo ""
echo "DEPLOYED SERVICE:"
kubectl describe services hello-service
echo ""
echo "DEPLOYED PODS:"
kubectl describe pods --selector app=hello-app
PORT=$( kubectl get services | grep hello-service | sed 's/.*:\([0-9]*\).*/\1/g' )
echo ""
echo "VIEW THE APPLICATION AT: http://$IP_ADDR:$PORT"