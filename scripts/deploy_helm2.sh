#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_helm.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_helm.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "CHART_NAME=${CHART_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"

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
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

# Using 'upgrade --install" for rolling updates. Note that subsequent updates will occur in the same namespace the release is currently deployed in, ignoring the explicit--namespace argument".
echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade --install --debug --dry-run ${RELEASE_NAME} ./chart/${CHART_NAME} --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade  --install ${RELEASE_NAME} ./chart/${CHART_NAME} --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

# Install jq tool
WORKING_DIR=$(pwd)
mkdir ~/tmpbin && cd ~/tmpbin
curl -sL "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64" -o jq && chmod +x jq
export PATH=$(pwd):$PATH
cd $WORKING_DIR

echo "=========================================================="
echo -e "CHECKING deployment status of release ${RELEASE_NAME} with image tag: ${IMAGE_TAG}"
echo ""
for ITERATION in {1..30}
do
  DATA=$( kubectl get pods --namespace ${CLUSTER_NAMESPACE} -a -l release=${RELEASE_NAME} -o json )
  NOT_READY=$( echo $DATA | jq '.items[].status.containerStatuses[] | select(.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | select(.ready==false) ' )
  if [[ -z "$NOT_READY" ]]; then
    echo -e "All pods are ready:"
    echo $DATA | jq '.items[].status.containerStatuses[] | select(.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | select(.ready==true) '
    break # deployment succeeded
  fi
  REASON=$(echo $DATA | jq '.items[].status.containerStatuses[] | select(.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | .state.waiting.reason')
  echo -e "${ITERATION} : Deployment still pending..."
  echo -e "NOT_READY:${NOT_READY}"
  echo -e "REASON: ${REASON}"
  if [[ "${REASON}" == *"ErrImagePull"* ]] || [[ "${REASON}" == *"ImagePullBackOff"* ]]; then
    echo "Detected ErrImagePull or ImagePullBackOff failure. "
    echo "Please check proper authenticating to from cluster to image registry (e.g. image pull secret)"
    break; # no need to wait longer, error is fatal
  fi
  sleep 5
done

if [[ ! -z "$NOT_READY" ]]; then
  echo ""
  echo "=========================================================="
  echo "DEPLOYMENT FAILED"
  echo "Deployed Services:"
  kubectl describe services ${RELEASE_NAME}-${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
  echo ""
  echo "Deployed Pods:"
  kubectl describe pods --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
  echo "=========================================================="
  PREVIOUS_RELEASE=$( helm history ${RELEASE_NAME} | grep SUPERSEDED | sort -r -n | awk '{print $1}' | head -n 1 )
  echo -e "Could rollback to previous release: ${PREVIOUS_RELEASE} using command:"
  echo -e "helm rollback ${RELEASE_NAME} ${PREVIOUS_RELEASE}"
  # helm rollback ${RELEASE_NAME} ${PREVIOUS_RELEASE}
  # echo -e "History for release:${RELEASE_NAME}"
  # helm history ${RELEASE_NAME}
  # echo "Deployed Services:"
  # kubectl describe services ${RELEASE_NAME}-${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
  # echo ""
  # echo "Deployed Pods:"
  # kubectl describe pods --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
  exit 1
fi

echo ""
echo "=========================================================="
echo "DEPLOYMENT SUCCEEDED"
echo ""
echo -e "Status for release:${RELEASE_NAME}"
helm status ${RELEASE_NAME}

echo ""
echo -e "History for release:${RELEASE_NAME}"
helm history ${RELEASE_NAME}

# echo ""
# echo "Deployed Services:"
# kubectl describe services ${RELEASE_NAME}-${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
# echo ""
# echo "Deployed Pods:"
# kubectl describe pods --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}

echo "=========================================================="
IP_ADDR=$(bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | head -n 1 | awk '{ print $2 }')
PORT=$(kubectl get services --namespace ${CLUSTER_NAMESPACE} | grep ${RELEASE_NAME} | sed 's/.*:\([0-9]*\).*/\1/g')
echo -e "View the application at: http://${IP_ADDR}:${PORT}"