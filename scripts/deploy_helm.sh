#!/bin/bash

# Input parameters configured via Env Variables
# RELEASE_NAME
# CHART_NAME

# Input parameters configured by Pipeline job automatically
# PIPELINE_KUBERNETES_CLUSTER_NAME
# CLUSTER_NAMESPACE
# REGISTRY_URL

#set -x

#View build properties
cat build.properties

#Check cluster availability
echo "=========================================================="
echo "Checking cluster"
IP_ADDR=$(bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | awk '{ print $2 }')
if [ -z ${IP_ADDR} ]; then
  echo -e "${PIPELINE_KUBERNETES_CLUSTER_NAME} not created or workers not ready"
  exit 1
fi

#Check cluster target namespace 
if kubectl get namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace ${CLUSTER_NAMESPACE}
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

# Grant access to private image registry from namespace $CLUSTER_NAMESPACE
# reference https://console.bluemix.net/docs/containers/cs_cluster.html#bx_registry_other
echo -e "Checking access to private image registry from namespace ${CLUSTER_NAMESPACE}"
IMAGE_PULL_SECRET_NAME="bluemix-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"
echo -e "create ${IMAGE_PULL_SECRET_NAME} imagePullSecret if it does not exist"
if ! kubectl get secret ${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}; then
  echo -e "${IMAGE_PULL_SECRET_NAME} not found in ${CLUSTER_NAMESPACE}, creating it"
  # for Container Registry, docker username is 'token' and email does not matter
  kubectl --namespace ${CLUSTER_NAMESPACE} create secret docker-registry ${IMAGE_PULL_SECRET_NAME} --docker-server=${REGISTRY_URL} --docker-password=${REGISTRY_TOKEN} --docker-username=token --docker-email=a@b.com
  echo "enable default serviceaccount to use the pull secret"
  kubectl patch -n ${CLUSTER_NAMESPACE} serviceaccount/default -p '{"imagePullSecrets":[{"name":"'"${IMAGE_PULL_SECRET_NAME}"'"}]}'
  echo -e "Namespace ${CLUSTER_NAMESPACE} is now authorized to pull from the private image registry"
fi
echo "default serviceAccount:"
kubectl get serviceAccount default -o yaml

echo "TODO -- do not patch the account, rather inject secret into the chart"

echo "=========================================================="
echo "Checking TILLER enabled (Helm's server component)"
helm init --upgrade
while true; do
  TILLER_DEPLOYED=$(kubectl --namespace=kube-system get pods | grep tiller | grep Running | grep 1/1 )
  if [[ "${TILLER_DEPLOYED}" != "" ]]; then
    echo "Tiller ready."
    break; 
  fi
  echo "Waiting for Tiller to be ready."
  sleep 1
done
helm version

echo "=========================================================="
echo "Checking Helm Chart"
helm lint ${RELEASE_NAME} ./chart/${CHART_NAME}

echo "=========================================================="
echo "Deploying Helm Chart"

echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ./chart/${CHART_NAME} --namespace $CLUSTER_NAMESPACE --install --debug --dry-run

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade ${RELEASE_NAME} ./chart/${CHART_NAME} --namespace ${CLUSTER_NAMESPACE} --install

echo ""
echo "Deployed Services:"
kubectl describe services ${RELEASE_NAME}-${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}

echo ""
echo "Deployed Pods:"
kubectl describe pods --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}

echo ""
echo "=========================================================="
PORT=$(kubectl get services --namespace ${CLUSTER_NAMESPACE} | grep ${RELEASE_NAME}-${CHART_NAME} | sed 's/.*:\([0-9]*\).*/\1/g')
echo -e "View the application at: http://${IP_ADDR}:${PORT}"