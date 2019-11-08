#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_helm.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_helm.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh")
# ------------------

# Perform a helm deploy of container image and check on outcome

# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "CHART_ROOT=${CHART_ROOT}"
echo "CHART_NAME=${CHART_NAME}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "USE_ISTIO_GATEWAY=${USE_ISTIO_GATEWAY}"
echo "HELM_VERSION=${HELM_VERSION}"

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

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
if [ -z "${CLUSTER_NAMESPACE}" ]; then CLUSTER_NAMESPACE=default ; fi
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

echo "=========================================================="
echo "CHECKING HELM CHART"
if [ -z "${CHART_ROOT}" ]; then CHART_ROOT="chart" ; fi
if [ -d ${CHART_ROOT} ]; then
  echo -e "Looking for chart under /${CHART_ROOT}/<CHART_NAME>"
  CHART_NAME=$(find ${CHART_ROOT}/. -maxdepth 2 -type d -name '[^.]?*' -printf %f -quit)
  CHART_PATH=${CHART_ROOT}/${CHART_NAME}
fi
if [ -z "${CHART_PATH}" ]; then
    echo -e "No Helm chart found for Kubernetes deployment under ${CHART_ROOT}/<CHART_NAME>."
    exit 1
else
    echo -e "Helm chart found for Kubernetes deployment : ${CHART_PATH}"
fi

echo "=========================================================="
if [ -z "$RELEASE_NAME" ]; then
  echo "DEFINE RELEASE by prefixing image (app) name with namespace if not 'default' as Helm needs unique release names across namespaces"
  if [[ "${CLUSTER_NAMESPACE}" != "default" ]]; then
    RELEASE_NAME="${CLUSTER_NAMESPACE}-${IMAGE_NAME}"
  else
    RELEASE_NAME=${IMAGE_NAME}
  fi
fi
echo -e "Release name: ${RELEASE_NAME}"

echo "=========================================================="
echo "CHECKING HELM CLIENT VERSION: matching Helm Tiller (server) if detected. "
set +e
LOCAL_VERSION=$( helm version --client ${HELM_TLS_OPTION} | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
TILLER_VERSION=$( helm version --server ${HELM_TLS_OPTION} | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
set -e
if [ -z "${TILLER_VERSION}" ]; then
  if [ -z "${HELM_VERSION}" ]; then
    CLIENT_VERSION=${LOCAL_VERSION}
  else
    CLIENT_VERSION=${HELM_VERSION}
  fi
else
  echo -e "Helm Tiller ${TILLER_VERSION} already installed in cluster. Keeping it, and aligning client."
  CLIENT_VERSION=${TILLER_VERSION}
fi
if [ "${CLIENT_VERSION}" != "${LOCAL_VERSION}" ]; then
  echo -e "Installing Helm client ${CLIENT_VERSION}"
  WORKING_DIR=$(pwd)
  mkdir ~/tmpbin && cd ~/tmpbin
  curl -L https://storage.googleapis.com/kubernetes-helm/helm-v${CLIENT_VERSION}-linux-amd64.tar.gz -o helm.tar.gz && tar -xzvf helm.tar.gz
  cd linux-amd64
  export PATH=$(pwd):$PATH
  cd $WORKING_DIR
fi
helm version --client

echo "=========================================================="
echo "DEPLOYING HELM chart"
IMAGE_REPOSITORY=${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

# Using 'upgrade --install" for rolling updates. Note that subsequent updates will occur in the same namespace the release is currently deployed in, ignoring the explicit--namespace argument".
echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ${CHART_PATH} ${HELM_TLS_OPTION} --install --debug --dry-run --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} ${HELM_UPGRADE_EXTRA_ARGS} --namespace ${CLUSTER_NAMESPACE}

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ${CHART_PATH} ${HELM_TLS_OPTION} --install --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} ${HELM_UPGRADE_EXTRA_ARGS} --namespace ${CLUSTER_NAMESPACE}

echo "=========================================================="
echo -e "CHECKING deployment status of release ${RELEASE_NAME} with image tag: ${IMAGE_TAG}"
# Extract name from actual Kube deployment resource owning the deployed container image 
DEPLOYMENT_NAME=$( helm get ${HELM_TLS_OPTION} ${RELEASE_NAME} | yq read -d'*' --tojson - | jq -r | jq -r --arg image "$IMAGE_REPOSITORY:$IMAGE_TAG" '.[] | select (.kind=="Deployment") | . as $adeployment | .spec?.template?.spec?.containers[]? | select (.image==$image) | $adeployment.metadata.name' )
echo -e "CHECKING deployment rollout of ${DEPLOYMENT_NAME}"
echo ""
set -x
if kubectl rollout status deploy/${DEPLOYMENT_NAME} --watch=true --timeout=150s --namespace ${CLUSTER_NAMESPACE}; then
  STATUS="pass"
else
  STATUS="fail"
fi
set +x

if [[ "$STATUS" == "fail" ]]; then
  echo ""
  echo "=========================================================="
  echo "DEPLOYMENT FAILED"
  echo "Deployed Services:"
  kubectl describe services --namespace ${CLUSTER_NAMESPACE}
  echo ""
  echo "Deployed Pods:"
  kubectl describe pods --namespace ${CLUSTER_NAMESPACE}
  echo ""
  # Record failing deploy information
  if jq -e '.services[] | select(.service_id=="draservicebroker")' _toolchain.json > /dev/null 2>&1; then
    ibmcloud doi publishdeployrecord --env "${PIPELINE_KUBERNETES_CLUSTER_NAME}:${CLUSTER_NAMESPACE}" --logicalappname="${APPLICATION_NAME:-$IMAGE_NAME}" --buildnumber="$GIT_BRANCH:$SOURCE_BUILD_NUMBER" --status=fail
  fi
  #echo "Application Logs"
  #kubectl logs --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
  echo "=========================================================="
  PREVIOUS_RELEASE=$( helm history ${HELM_TLS_OPTION} ${RELEASE_NAME} | grep SUPERSEDED | sort -r -n | awk '{print $1}' | head -n 1 )
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
echo "DEPLOYMENTS:"
echo ""
echo -e "Status for release:${RELEASE_NAME}"
helm status ${HELM_TLS_OPTION} ${RELEASE_NAME}

echo ""
echo -e "History for release:${RELEASE_NAME}"
helm history ${HELM_TLS_OPTION} ${RELEASE_NAME}

echo "=========================================================="
APP_NAME=$( helm get ${HELM_TLS_OPTION} ${RELEASE_NAME} | yq read -d'*' --tojson - | jq -r | jq -r --arg image "$IMAGE_REPOSITORY:$IMAGE_TAG" '.[] | select (.kind=="Deployment") | . as $adeployment | .spec?.template?.spec?.containers[]? | select (.image==$image) | $adeployment.metadata.labels.app' )
echo -e "APP: ${APP_NAME}"
echo "DEPLOYED PODS:"
kubectl describe pods --selector app=${APP_NAME} --namespace ${CLUSTER_NAMESPACE}

# lookup service for current release
APP_SERVICE=$(kubectl get services --namespace ${CLUSTER_NAMESPACE} -o json | jq -r ' .items[] | select (.spec.selector.release=="'"${RELEASE_NAME}"'") | .metadata.name ')
if [ -z "${APP_SERVICE}" ]; then
  # lookup service for current app
  APP_SERVICE=$(kubectl get services --namespace ${CLUSTER_NAMESPACE} -o json | jq -r ' .items[] | select (.spec.selector.app=="'"${APP_NAME}"'") | .metadata.name ')
fi
if [ ! -z "${APP_SERVICE}" ]; then
  echo -e "SERVICE: ${APP_SERVICE}"
  echo "DEPLOYED SERVICES:"
  kubectl describe services ${APP_SERVICE} --namespace ${CLUSTER_NAMESPACE}
fi

echo ""
echo "=========================================================="
echo "DEPLOYMENT SUCCEEDED"
# Record passing deploy information
if jq -e '.services[] | select(.service_id=="draservicebroker")' _toolchain.json > /dev/null 2>&1; then
  ibmcloud doi publishdeployrecord --env "${PIPELINE_KUBERNETES_CLUSTER_NAME}:${CLUSTER_NAMESPACE}" --logicalappname="${APPLICATION_NAME:-$IMAGE_NAME}" --buildnumber="$GIT_BRANCH:$SOURCE_BUILD_NUMBER" --status=pass
fi
if [ ! -z "${APP_SERVICE}" ]; then
  echo ""
  echo ""
  if [ -z "${KUBERNETES_MASTER_ADDRESS}" ]; then  
    IP_ADDR=$(bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | head -n 1 | awk '{ print $2 }')
  else
    IP_ADDR=${KUBERNETES_MASTER_ADDRESS}
  fi
  if [ "${USE_ISTIO_GATEWAY}" = true ]; then
    PORT=$( kubectl get svc istio-ingressgateway -n istio-system -o json | jq -r '.spec.ports[] | select (.name=="http2") | .nodePort ' )
    echo -e "*** istio gateway enabled ***"
  else
    PORT=$( kubectl get service ${APP_SERVICE} --namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.spec.ports[0].nodePort' )
  fi
  export APP_URL=${APP_URL_SCHEME:-'http'}://${IP_ADDR}:${PORT}${APP_URL_PATH}
  echo -e "VIEW THE APPLICATION AT: ${APP_URL}"
fi