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