#!/bin/bash
# uncomment to debug the script
#set -x

echo "Input env variables (can be received via properties.file:"
echo "CHART_NAME=${CHART_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "REGISTRY_TOKEN=${REGISTRY_TOKEN}"
#View build properties
# cat build.properties

# Input parameters configured by Pipeline job automatically
# PIPELINE_KUBERNETES_CLUSTER_NAME
# CLUSTER_NAMESPACE

#set -x

#View build properties
cat build.properties

#Check cluster availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
IP_ADDR=$(bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | awk '{ print $2 }')
if [ -z ${IP_ADDR} ]; then
  echo -e "${PIPELINE_KUBERNETES_CLUSTER_NAME} not created or workers not ready"
  exit 1
fi

echo "Configuring cluster namespace"
if kubectl get namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace ${CLUSTER_NAMESPACE}
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

# Grant access to private image registry from namespace $CLUSTER_NAMESPACE
# reference https://console.bluemix.net/docs/containers/cs_cluster.html#bx_registry_other
echo "=========================================================="
echo -e "CONFIGURING ACCESS to private image registry from namespace ${CLUSTER_NAMESPACE}"
IMAGE_PULL_SECRET_NAME="bluemix-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"
echo -e "Checking for presence of ${IMAGE_PULL_SECRET_NAME} imagePullSecret for this toolchain"
if ! kubectl get secret ${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}; then
  echo -e "${IMAGE_PULL_SECRET_NAME} not found in ${CLUSTER_NAMESPACE}, creating it"
  # for Container Registry, docker username is 'token' and email does not matter
  kubectl --namespace ${CLUSTER_NAMESPACE} create secret docker-registry ${IMAGE_PULL_SECRET_NAME} --docker-server=${REGISTRY_URL} --docker-password=${REGISTRY_TOKEN} --docker-username=token --docker-email=a@b.com
  echo "enable default serviceaccount to use the pull secret"
  kubectl patch -n ${CLUSTER_NAMESPACE} serviceaccount/default -p '{"imagePullSecrets":[{"name":"'"${IMAGE_PULL_SECRET_NAME}"'"}]}'
  echo -e "Namespace ${CLUSTER_NAMESPACE} is now authorized to pull from the private image registry"
else
  echo -e "Namespace ${CLUSTER_NAMESPACE} is already authorized to pull from the private image registry"
fi
echo "default serviceAccount:"
kubectl get serviceAccount default -o yaml

echo "TODO -- do not patch the account, rather inject secret into the chart"

echo "=========================================================="
echo "CONFIGURING TILLER enabled (Helm server-side component)"
helm init --upgrade
while true; do
  TILLER_DEPLOYED=$(kubectl --namespace=kube-system get pods | grep tiller | grep Running | grep 1/1 )
  if [[ "${TILLER_DEPLOYED}" != "" ]]; then
    echo "Tiller is ready."
    break; 
  fi
  echo "Waiting for Tiller to become ready."
  sleep 1
done
helm version

echo "=========================================================="
echo -e "CHECKING HELM releases in this namespace: ${CLUSTER_NAMESPACE}"
helm list --namespace ${CLUSTER_NAMESPACE}