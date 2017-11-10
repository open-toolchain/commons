#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_helm.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_helm.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh")`
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "CHART_NAME=${CHART_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
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
echo "DEFINE RELEASE by prefixing image (app) name with namespace if not 'default' as Helm needs unique release names across namespaces"
if [[ "${CLUSTER_NAMESPACE}" != "default" ]]; then
  RELEASE_NAME="${CLUSTER_NAMESPACE}-${IMAGE_NAME}"
else
  RELEASE_NAME=${IMAGE_NAME}
fi
echo -e "Release name: ${RELEASE_NAME}"

echo "=========================================================="
echo "DEPLOYING HELM chart"
IMAGE_REPOSITORY=${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}

# Using 'upgrade --install" for rolling updates. Note that subsequent updates will occur in the same namespace the release is currently deployed in, ignoring the explicit--namespace argument".
echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ./chart/${CHART_NAME} --set image.repository=${IMAGE_REPOSITORY},image.tag=${BUILD_NUMBER} --namespace ${CLUSTER_NAMESPACE} --install --debug --dry-run

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ./chart/${CHART_NAME} --set image.repository=${IMAGE_REPOSITORY},image.tag=${BUILD_NUMBER} --namespace ${CLUSTER_NAMESPACE} --install

echo "=========================================================="
echo "CHECKING OUTCOME"
echo ""
echo -e "History for release:${RELEASE_NAME}"
helm history ${RELEASE_NAME}

echo ""
echo -e "Releases in namespace: ${CLUSTER_NAMESPACE}"
helm list --namespace ${CLUSTER_NAMESPACE}

echo ""
echo "Deployed Services:"
kubectl describe services ${RELEASE_NAME}-${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}

echo ""
echo "Deployed Pods:"
kubectl describe pods --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}

echo ""
echo "=========================================================="
#Check cluster availability
echo "=========================================================="
IP_ADDR=$(bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | awk '{ print $2 }')
PORT=$(kubectl get services --namespace ${CLUSTER_NAMESPACE} | grep ${PREFIXED_RELEASE_NAME}-${CHART_NAME} | sed 's/.*:\([0-9]*\).*/\1/g')
echo -e "View the application at: http://${IP_ADDR}:${PORT}"