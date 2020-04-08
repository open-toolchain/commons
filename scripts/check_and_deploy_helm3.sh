#!/bin/bash
# This script checks the IBM Container Service cluster is ready, has a namespace configured with access to the private
# image registry (using an IBM Cloud API Key), perform a Helm deploy of container image using Helm 3 and check on outcome.
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_and_deploy_helm3.sh) and 'source' it from your pipeline job
#    source ./scripts/check_and_deploy_helm3.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_and_deploy_helm3.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_and_deploy_helm3.sh

# This script checks the IBM Container Service cluster is ready, has a namespace configured with access to the private
# image registry (using an IBM Cloud API Key), perform a Helm deploy of container image using Helm 3 and check on outcome.

# Input env variables (can be received via a pipeline environment properties.file.
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "CHART_ROOT=${CHART_ROOT}"
echo "CHART_NAME=${CHART_NAME}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "DEPLOYMENT_FILE=${DEPLOYMENT_FILE}"
echo "USE_ISTIO_GATEWAY=${USE_ISTIO_GATEWAY}"
echo "HELM_VERSION=${HELM_VERSION}"
echo "KUBERNETES_SERVICE_ACCOUNT_NAME=${KUBERNETES_SERVICE_ACCOUNT_NAME}"

echo "Use for custom Kubernetes cluster target:"
echo "KUBERNETES_MASTER_ADDRESS=${KUBERNETES_MASTER_ADDRESS}"
echo "KUBERNETES_MASTER_PORT=${KUBERNETES_MASTER_PORT}"
echo "KUBERNETES_SERVICE_ACCOUNT_TOKEN=${KUBERNETES_SERVICE_ACCOUNT_TOKEN}"

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
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

# If custom cluster credentials available, connect to this cluster instead
if [ ! -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
  kubectl config set-cluster custom-cluster --server=https://${KUBERNETES_MASTER_ADDRESS}:${KUBERNETES_MASTER_PORT} --insecure-skip-tls-verify=true
  kubectl config set-credentials sa-user --token="${KUBERNETES_SERVICE_ACCOUNT_TOKEN}"
  kubectl config set-context custom-context --cluster=custom-cluster --user=sa-user --namespace="${CLUSTER_NAMESPACE}"
  kubectl config use-context custom-context
fi
# Use kubectl auth to check if the kubectl client configuration is appropriate
# check if the current configuration can create a deployment in the target namespace
echo "Check ability to create a kubernetes deployment in ${CLUSTER_NAMESPACE} using kubectl CLI"
kubectl auth can-i create deployment --namespace ${CLUSTER_NAMESPACE}

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
echo "Linting Helm Chart"
helm lint ${CHART_PATH}

#Check cluster availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
if [ -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
  IP_ADDR=$( ibmcloud ks workers --cluster ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | head -n 1 | awk '{ print $2 }' )
  if [ -z "${IP_ADDR}" ]; then
    echo -e "${PIPELINE_KUBERNETES_CLUSTER_NAME} not created or workers not ready"
    exit 1
  fi
fi
echo "Configuring cluster namespace"
if kubectl get namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace ${CLUSTER_NAMESPACE}
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

# Grant access to private image registry from namespace $CLUSTER_NAMESPACE
# reference https://cloud.ibm.com/docs/containers/cs_cluster.html#bx_registry_other
echo "=========================================================="
echo -e "CONFIGURING ACCESS to private image registry from namespace ${CLUSTER_NAMESPACE}"
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

echo -e "Checking for presence of ${IMAGE_PULL_SECRET_NAME} imagePullSecret for this toolchain"
if ! kubectl get secret ${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}; then
  echo -e "${IMAGE_PULL_SECRET_NAME} not found in ${CLUSTER_NAMESPACE}, creating it"
  # for Container Registry, docker username is 'token' and email does not matter
  if [ -z "${PIPELINE_BLUEMIX_API_KEY}" ]; then PIPELINE_BLUEMIX_API_KEY=${IBM_CLOUD_API_KEY}; fi #when used outside build-in kube job
  kubectl --namespace ${CLUSTER_NAMESPACE} create secret docker-registry ${IMAGE_PULL_SECRET_NAME} --docker-server=${REGISTRY_URL} --docker-password=${PIPELINE_BLUEMIX_API_KEY} --docker-username=iamapikey --docker-email=a@b.com
else
  echo -e "Namespace ${CLUSTER_NAMESPACE} already has an imagePullSecret for this toolchain."
fi
echo "Checking ability to pass pull secret via Helm chart (see also https://cloud.ibm.com/docs/containers/cs_images.html#images)"
CHART_PULL_SECRET=$( grep 'pullSecret' ${CHART_PATH}/values.yaml || : )
if [ -z "${CHART_PULL_SECRET}" ]; then
  echo "INFO: Chart is not expecting an explicit private registry imagePullSecret. Patching the cluster default serviceAccount to pass it implicitly instead."
  echo "      Learn how to inject pull secrets into the deployment chart at: https://kubernetes.io/docs/concepts/containers/images/#referring-to-an-imagepullsecrets-on-a-pod"
  echo "      or check out this chart example: https://github.com/open-toolchain/hello-helm/tree/master/chart/hello"
  if [ -z "${KUBERNETES_SERVICE_ACCOUNT_NAME}" ]; then KUBERNETES_SERVICE_ACCOUNT_NAME="default" ; fi
  SERVICE_ACCOUNT=$(kubectl get serviceaccount ${KUBERNETES_SERVICE_ACCOUNT_NAME}  -o json --namespace ${CLUSTER_NAMESPACE} )
  if ! echo ${SERVICE_ACCOUNT} | jq -e '. | has("imagePullSecrets")' > /dev/null ; then
    kubectl patch --namespace ${CLUSTER_NAMESPACE} serviceaccount/default -p '{"imagePullSecrets":[{"name":"'"${IMAGE_PULL_SECRET_NAME}"'"}]}'
  else
    if echo ${SERVICE_ACCOUNT} | jq -e '.imagePullSecrets[] | select(.name=="'"${IMAGE_PULL_SECRET_NAME}"'")' > /dev/null ; then 
      echo -e "Pull secret already found in ${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount"
    else
      echo "Inserting toolchain pull secret into ${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount"
      kubectl patch --namespace ${CLUSTER_NAMESPACE} serviceaccount/${KUBERNETES_SERVICE_ACCOUNT_NAME} --type='json' -p='[{"op":"add","path":"/imagePullSecrets/-","value":{"name": "'"${IMAGE_PULL_SECRET_NAME}"'"}}]'
    fi
  fi
  echo "${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount:"
  kubectl get serviceaccount ${KUBERNETES_SERVICE_ACCOUNT_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml
  echo -e "Namespace ${CLUSTER_NAMESPACE} authorizing with private image registry using patched ${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount"  
else
  echo -e "Namespace ${CLUSTER_NAMESPACE} authorized with private image registry using Helm chart imagePullSecret"
fi

echo "=========================================================="
echo "CHECKING HELM 3 VERSION (if absent will install latest Helm 3 version) "
set +e
LOCAL_VERSION=$( helm version ${HELM_TLS_OPTION} --template="{{ .Version }}" | cut -c 2- )
# if no Helm 3 locally installed, LOCAL_VERSION will be empty -- will install latest then
set -e
if [ -z "${HELM_VERSION}" ]; then
  CLIENT_VERSION=${LOCAL_VERSION} 
else
  CLIENT_VERSION=${HELM_VERSION}
fi

if [ -z "${CLIENT_VERSION}" ]; then # Helm 3 not present yet and no explicit required version, install latest
  echo "Installing latest Helm 3 client"
  WORKING_DIR=$(pwd)
  mkdir ~/tmpbin && cd ~/tmpbin
  HELM_INSTALL_DIR=$(pwd)
  curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
  export PATH=${HELM_INSTALL_DIR}:$PATH
  cd $WORKING_DIR
elif [ "${CLIENT_VERSION}" != "${LOCAL_VERSION}" ]; then
  echo -e "Installing Helm 3 client ${CLIENT_VERSION}"
  WORKING_DIR=$(pwd)
  mkdir ~/tmpbin && cd ~/tmpbin
  curl -L https://get.helm.sh/helm-v${CLIENT_VERSION}-linux-amd64.tar.gz -o helm.tar.gz && tar -xzvf helm.tar.gz
  cd linux-amd64
  export PATH=$(pwd):$PATH
  cd $WORKING_DIR
fi
helm version ${HELM_TLS_OPTION}

echo "=========================================================="
echo -e "CHECKING HELM releases in this namespace: ${CLUSTER_NAMESPACE}"
helm list ${HELM_TLS_OPTION} --namespace ${CLUSTER_NAMESPACE}

echo "=========================================================="
if [ -z "$RELEASE_NAME" ]; then
  # Helm3 releases are now scoped to namespaces. No need to make them unique across
  echo "DEFINE RELEASE by prefixing image (app) name with namespace if not 'default'"
  # if [[ "${CLUSTER_NAMESPACE}" != "default" ]]; then
  #   RELEASE_NAME="${CLUSTER_NAMESPACE}-${IMAGE_NAME}"
  # else
  RELEASE_NAME=${IMAGE_NAME}
  # fi
fi
echo -e "Release name: ${RELEASE_NAME}"

echo "=========================================================="
echo "DEPLOYING HELM chart"
IMAGE_REPOSITORY=${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

# Using 'upgrade --install" for rolling updates.".
echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ${CHART_PATH} ${HELM_TLS_OPTION} --install --debug --dry-run --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} ${HELM_UPGRADE_EXTRA_ARGS} --namespace ${CLUSTER_NAMESPACE}

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ${CHART_PATH} ${HELM_TLS_OPTION} --install --set image.repository=${IMAGE_REPOSITORY},image.tag=${IMAGE_TAG},image.pullSecret=${IMAGE_PULL_SECRET_NAME} ${HELM_UPGRADE_EXTRA_ARGS} --namespace ${CLUSTER_NAMESPACE}

echo "=========================================================="
echo -e "CHECKING deployment status of release ${RELEASE_NAME} with image tag: ${IMAGE_TAG}"
# Extract name from actual Kube deployment resource owning the deployed container image 
DEPLOYMENT_NAME=$( helm get manifest ${HELM_TLS_OPTION} ${RELEASE_NAME} --namespace ${CLUSTER_NAMESPACE} | yq read -d'*' --tojson - | jq -r | jq -r --arg image "$IMAGE_REPOSITORY:$IMAGE_TAG" '.[] | select (.kind=="Deployment") | . as $adeployment | .spec?.template?.spec?.containers[]? | select (.image==$image) | $adeployment.metadata.name' )
echo -e "CHECKING deployment rollout of ${DEPLOYMENT_NAME}"
echo ""
set -x
if kubectl rollout status deploy/${DEPLOYMENT_NAME} --watch=true --timeout=${ROLLOUT_TIMEOUT:-"150s"} --namespace ${CLUSTER_NAMESPACE}; then
  STATUS="pass"
else
  STATUS="fail"
fi
set +x

# Dump events that occured during the rollout
echo "SHOWING last events"
kubectl get events --sort-by=.metadata.creationTimestamp -n ${CLUSTER_NAMESPACE}

# Record deploy information
if jq -e '.services[] | select(.service_id=="draservicebroker")' _toolchain.json > /dev/null 2>&1; then
  if [ -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
    DEPLOYMENT_ENVIRONMENT="${PIPELINE_KUBERNETES_CLUSTER_NAME}:${CLUSTER_NAMESPACE}"
  else 
    DEPLOYMENT_ENVIRONMENT="${KUBERNETES_MASTER_ADDRESS}:${CLUSTER_NAMESPACE}"
  fi
  ibmcloud doi publishdeployrecord --env $DEPLOYMENT_ENVIRONMENT \
    --buildnumber ${SOURCE_BUILD_NUMBER} --logicalappname ${IMAGE_NAME} --status ${STATUS}
fi
if [ "$STATUS" == "fail" ]; then
  echo "DEPLOYMENT FAILED"
  echo "Showing registry pull quota"
  ibmcloud cr quota || true
  echo "=========================================================="
  PREVIOUS_RELEASE=$( helm history ${HELM_TLS_OPTION} ${RELEASE_NAME} --namespace ${CLUSTER_NAMESPACE} | grep SUPERSEDED | sort -r -n | awk '{print $1}' | head -n 1 )
  echo -e "Could rollback to previous release: ${PREVIOUS_RELEASE} using command:"
  echo -e "helm rollback ${RELEASE_NAME} ${PREVIOUS_RELEASE}"
  # helm rollback ${RELEASE_NAME} ${PREVIOUS_RELEASE} --namespace ${CLUSTER_NAMESPACE}
  # echo -e "History for release:${RELEASE_NAME}"
  # helm history ${RELEASE_NAME} --namespace ${CLUSTER_NAMESPACE}
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
helm status ${HELM_TLS_OPTION} ${RELEASE_NAME} --namespace ${CLUSTER_NAMESPACE}

echo ""
echo -e "History for release:${RELEASE_NAME}"
helm history ${HELM_TLS_OPTION} ${RELEASE_NAME} --namespace ${CLUSTER_NAMESPACE}

# Extract app name from helm release
echo "=========================================================="
APP_NAME=$( helm get manifest ${HELM_TLS_OPTION} ${RELEASE_NAME} --namespace ${CLUSTER_NAMESPACE} | yq read -d'*' --tojson - | jq -r | jq -r --arg image "$IMAGE_REPOSITORY:$IMAGE_TAG" '.[] | select (.kind=="Deployment") | . as $adeployment | .spec?.template?.spec?.containers[]? | select (.image==$image) | $adeployment.metadata.labels.app' )
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
if [ ! -z "${APP_SERVICE}" ]; then
  echo ""
  if [ "${USE_ISTIO_GATEWAY}" = true ]; then
    PORT=$( kubectl get svc istio-ingressgateway -n istio-system -o json | jq -r '.spec.ports[] | select (.name=="http2") | .nodePort ' )
    echo -e "*** istio gateway enabled ***"
  else
    PORT=$( kubectl get services --namespace ${CLUSTER_NAMESPACE} | grep ${APP_SERVICE} | sed 's/.*:\([0-9]*\).*/\1/g' )
  fi
  if [ -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
    echo "Using first worker node ip address as NodeIP: ${IP_ADDR}"
  else 
    # check if a route resource exists in the this kubernetes cluster
    if kubectl explain route > /dev/null 2>&1; then
      # Assuming the kubernetes target cluster is an openshift cluster
      # Check if a route exists for exposing the service ${APP_SERVICE}
      if  kubectl get routes --namespace ${CLUSTER_NAMESPACE} -o json | jq --arg service "$APP_SERVICE" -e '.items[] | select(.spec.to.name==$service)'; then
        echo "Existing route to expose service $APP_SERVICE"
      else
        # create OpenShift route
cat > test-route.json << EOF
{"apiVersion":"route.openshift.io/v1","kind":"Route","metadata":{"name":"${APP_SERVICE}"},"spec":{"to":{"kind":"Service","name":"${APP_SERVICE}"}}}
EOF
        echo ""
        cat test-route.json
        kubectl apply -f test-route.json --validate=false --namespace ${CLUSTER_NAMESPACE}
        kubectl get routes --namespace ${CLUSTER_NAMESPACE}
      fi
      echo "LOOKING for host in route exposing service $APP_SERVICE"
      IP_ADDR=$(kubectl get routes --namespace ${CLUSTER_NAMESPACE} -o json | jq --arg service "$APP_SERVICE" -r '.items[] | select(.spec.to.name==$service) | .status.ingress[0].host')
      PORT=80
    else
      # Use the KUBERNETES_MASTER_ADRESS
      IP_ADDR=${KUBERNETES_MASTER_ADDRESS}
    fi
  fi  
  export APP_URL=http://${IP_ADDR}:${PORT} # using 'export', the env var gets passed to next job in stage
  echo -e "VIEW THE APPLICATION AT: ${APP_URL}"
fi