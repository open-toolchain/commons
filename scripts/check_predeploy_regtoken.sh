#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_predeploy_regtoken.sh) and 'source' it from your pipeline job
#    source ./scripts/check_predeploy_regtoken.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_predeploy_regtoken.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_predeploy_regtoken.sh

# This script checks the IBM Container Service cluster is ready, has a namespace configured with access to the private
# image registry (using a registry token passed in argument). It also configures Helm Tiller service to later perform a deploy with Helm.

# Input env variables (can be received via a pipeline environment properties.file.
echo "CHART_NAME=${CHART_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "PIPELINE_STAGE_INPUT_REV=${PIPELINE_STAGE_INPUT_REV}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "REGISTRY_TOKEN=${REGISTRY_TOKEN}"

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

#Check cluster availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
CLUSTER_ID=${PIPELINE_KUBERNETES_CLUSTER_ID:-${PIPELINE_KUBERNETES_CLUSTER_NAME}} # use cluster id instead of cluster name to handle case where there are multiple clusters with same name
IP_ADDR=$( ibmcloud ks workers --cluster ${CLUSTER_ID} | grep normal | head -n 1 | awk '{ print $2 }' )
if [ -z "${IP_ADDR}" ]; then
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
# reference https://cloud.ibm.com/docs/containers/cs_cluster.html#bx_registry_other
echo "=========================================================="
echo -e "CONFIGURING ACCESS to private image registry from namespace ${CLUSTER_NAMESPACE}"
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"
echo -e "Checking for presence of ${IMAGE_PULL_SECRET_NAME} imagePullSecret for this toolchain"
if ! kubectl get secret ${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}; then
  echo -e "${IMAGE_PULL_SECRET_NAME} not found in ${CLUSTER_NAMESPACE}, creating it"
  # for Container Registry, docker username is 'token' and email does not matter
  kubectl --namespace ${CLUSTER_NAMESPACE} create secret docker-registry ${IMAGE_PULL_SECRET_NAME} --docker-server=${REGISTRY_URL} --docker-password=${REGISTRY_TOKEN} --docker-username=token --docker-email=a@b.com
else
  echo -e "Namespace ${CLUSTER_NAMESPACE} already has an imagePullSecret for this toolchain."
fi
echo "Checking ability to pass pull secret via Helm chart"
CHART_PULL_SECRET=$( grep 'pullSecret' ./chart/${CHART_NAME}/values.yaml || : )
if [ -z "$CHART_PULL_SECRET" ]; then
  echo "WARNING: Chart is not expecting an explicit private registry imagePullSecret. Will patch the cluster default serviceAccount to pass it implicitly for now."
  echo "Going forward, you should edit the chart to add in:"
  echo -e "[./chart/${CHART_NAME}/templates/deployment.yaml] (under kind:Deployment)"
  echo "    ..."
  echo "    spec:"
  echo "      imagePullSecrets:               #<<<<<<<<<<<<<<<<<<<<<<<<"
  echo "        - name: {{ .Values.image.pullSecret }}   #<<<<<<<<<<<<<<<<<<<<<<<<"
  echo "      containers:"
  echo "        - name: {{ .Chart.Name }}"
  echo "          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  echo "    ..."          
  echo -e "[./chart/${CHART_NAME}/values.yaml]"
  echo "or check out this chart example: https://github.com/open-toolchain/hello-helm/tree/master/chart/hello"
  echo "or refer to: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/#create-a-pod-that-uses-your-secret"
  echo "    ..."
  echo "    image:"
  echo "repository: webapp"
  echo "  tag: 1"
  echo "  pullSecret: regsecret            #<<<<<<<<<<<<<<<<<<<<<<<<""
  echo "  pullPolicy: IfNotPresent"
  echo "    ..."
  echo "Enabling default serviceaccount to use the pull secret"
  kubectl patch -n ${CLUSTER_NAMESPACE} serviceaccount/default -p '{"imagePullSecrets":[{"name":"'"${IMAGE_PULL_SECRET_NAME}"'"}]}'
  echo "default serviceAccount:"
  kubectl get serviceAccount default -o yaml
  echo -e "Namespace ${CLUSTER_NAMESPACE} authorizing with private image registry using patched default serviceAccount"
else
  echo -e "Namespace ${CLUSTER_NAMESPACE} authorizing with private image registry using Helm chart imagePullSecret"
fi

echo "=========================================================="
echo "CONFIGURING TILLER enabled (Helm server-side component)"
helm init --upgrade --force-upgrade
kubectl rollout status -w deployment/tiller-deploy --namespace=kube-system
helm version

echo "=========================================================="
echo -e "CHECKING HELM releases in this namespace: ${CLUSTER_NAMESPACE}"
helm list --namespace ${CLUSTER_NAMESPACE}