#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_helm.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_helm.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "CHART_ROOT=${CHART_ROOT}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "USE_ISTIO_GATEWAY=${USE_ISTIO_GATEWAY}"
echo "HELM_VERSION=${HELM_VERSION}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
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
echo -e "Looking for chart under /${CHART_ROOT}/<CHART_NAME>"
if [ -d ${CHART_ROOT} ]; then
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
echo "DEFINE RELEASE by prefixing image (app) name with namespace if not 'default' as Helm needs unique release names across namespaces"
if [[ "${CLUSTER_NAMESPACE}" != "default" ]]; then
  RELEASE_NAME="${CLUSTER_NAMESPACE}-${IMAGE_NAME}"
else
  RELEASE_NAME=${IMAGE_NAME}
fi
echo -e "Release name: ${RELEASE_NAME}"

echo "=========================================================="
echo "CHECKING HELM CLIENT VERSION: matching Helm Tiller (server) if detected. "
set +e
LOCAL_VERSION=$( helm version --client | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
TILLER_VERSION=$( helm version --server | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
set -e
if [ -z "${TILLER_VERSION}" ]; then
  if [ -z "${HELM_VERSION}" ]; then
    CLIENT_VERSION=${HELM_VERSION}
  else
    CLIENT_VERSION=${LOCAL_VERSION}
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
helm upgrade --install --debug --dry-run ${RELEASE_NAME} ${CHART_PATH} --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade  --install ${RELEASE_NAME} ${CHART_PATH} --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

echo "=========================================================="
echo -e "CHECKING deployment status of release ${RELEASE_NAME} with image tag: ${IMAGE_TAG}"
echo ""
for ITERATION in {1..30}
do
  DATA=$( kubectl get pods --namespace ${CLUSTER_NAMESPACE} -o json )
  NOT_READY=$( echo $DATA | jq '.items[].status | select(.containerStatuses!=null) | .containerStatuses[] | select(.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | select(.ready==false) ' )
  if [[ -z "$NOT_READY" ]]; then
    echo -e "All pods are ready:"
    echo $DATA | jq '.items[].status | select(.containerStatuses!=null) | .containerStatuses[] | select(.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | select(.ready==true) '
    break # deployment succeeded
  fi
  REASON=$(echo $DATA | jq '.items[].status | select(.containerStatuses!=null) | .containerStatuses[] | select(.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | .state.waiting.reason')
  echo -e "${ITERATION} : Deployment still pending..."
  echo -e "NOT_READY:${NOT_READY}"
  echo -e "REASON: ${REASON}"
  if [[ ${REASON} == *ErrImagePull* ]] || [[ ${REASON} == *ImagePullBackOff* ]]; then
    echo "Detected ErrImagePull or ImagePullBackOff failure. "
    echo "Please check image still exists in registry, and proper permissions from cluster to image registry (e.g. image pull secret)"
    break; # no need to wait longer, error is fatal
  elif [[ ${REASON} == *CrashLoopBackOff* ]]; then
    echo "Detected CrashLoopBackOff failure. "
    echo "Application is unable to start, check the application startup logs"
    break; # no need to wait longer, error is fatal
  fi
  sleep 5
done

if [[ ! -z "$NOT_READY" ]]; then
  echo ""
  echo "=========================================================="
  echo "DEPLOYMENT FAILED"
  echo "Deployed Services:"
  kubectl describe services --namespace ${CLUSTER_NAMESPACE}
  echo ""
  echo "Deployed Pods:"
  kubectl describe pods --namespace ${CLUSTER_NAMESPACE}
  echo ""
  #echo "Application Logs"
  #kubectl logs --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
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
APP_NAME=$(kubectl get pods --namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.items[] | select(.spec.containers[]?.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | .metadata.labels.app')
echo -e "APP: ${APP_NAME}"
echo "DEPLOYED PODS:"
kubectl describe pods --selector app=${APP_NAME} --namespace ${CLUSTER_NAMESPACE}
if [ ! -z "${APP_NAME}" ]; then
  APP_SERVICE=$(kubectl get services --namespace ${CLUSTER_NAMESPACE} -o json | jq -r ' .items[] | select (.spec.selector.app=="'"${APP_NAME}"'") | .metadata.name ')
  echo -e "SERVICE: ${APP_SERVICE}"
  echo "DEPLOYED SERVICES:"
  kubectl describe services ${APP_SERVICE} --namespace ${CLUSTER_NAMESPACE}
fi
#echo "Application Logs"
#kubectl logs --selector app=${APP_NAME} --namespace ${CLUSTER_NAMESPACE}  
echo ""
if [[ ! -z "$NOT_READY" ]]; then
  echo ""
  echo "=========================================================="
  echo "DEPLOYMENT FAILED"
  exit 1
fi

echo ""
echo "=========================================================="
echo "DEPLOYMENT SUCCEEDED"
if [ ! -z "${APP_SERVICE}" ]; then
  echo ""
  echo ""
  IP_ADDR=$(bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | head -n 1 | awk '{ print $2 }')
  if [ "${USE_ISTIO_GATEWAY}" = true ]; then
    PORT=$( kubectl get svc istio-ingressgateway -n istio-system -o json | jq -r '.spec.ports[] | select (.name=="http2") | .nodePort ' )
    echo -e "*** istio gateway enabled ***"
  else
    PORT=$( kubectl get services --namespace ${CLUSTER_NAMESPACE} | grep ${APP_SERVICE} | sed 's/.*:\([0-9]*\).*/\1/g' )
  fi
  echo -e "VIEW THE APPLICATION AT: http://${IP_ADDR}:${PORT}"
fi