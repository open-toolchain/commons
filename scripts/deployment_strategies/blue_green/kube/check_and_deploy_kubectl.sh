#!/bin/bash
# This script checks the IBM Container Service cluster is ready, has a namespace configured with access to the private
# image registry (using an IBM Cloud API Key), perform a kubectl deploy of container image and check on outcome.
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_and_deploy_kubectl.sh) and 'source' it from your pipeline job
#    source ./scripts/check_and_deploy_kubectl.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deployment_stategies/blue_green/kube/check_and_deploy_kubectl.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deployment_stategies/blue_green/kube/check_and_deploy_kubectl.sh

# This script checks the IBM Container Service cluster is ready, has a namespace configured with access to the private
# image registry (using an IBM Cloud API Key), perform a kubectl deploy of container image and check on outcome.

# Input env variables (can be received via a pipeline environment properties.file.

echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "IMAGE_MANIFEST_SHA=${IMAGE_MANIFEST_SHA}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "DEPLOYMENT_FILE=${DEPLOYMENT_FILE}"
echo "USE_ISTIO_GATEWAY=${USE_ISTIO_GATEWAY}"
echo "KEEP_INGRESS_CUSTOM_DOMAIN=${KEEP_INGRESS_CUSTOM_DOMAIN}"
echo "KUBERNETES_SERVICE_ACCOUNT_NAME=${KUBERNETES_SERVICE_ACCOUNT_NAME}"

echo "Use for custom Kubernetes cluster target:"
echo "KUBERNETES_MASTER_ADDRESS=${KUBERNETES_MASTER_ADDRESS}"
echo "KUBERNETES_MASTER_PORT=${KUBERNETES_MASTER_PORT}"
echo "KUBERNETES_SERVICE_ACCOUNT_TOKEN=${KUBERNETES_SERVICE_ACCOUNT_TOKEN}"

if [ -z "${IMAGE_MANIFEST_SHA}" ]; then
  IMAGE="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"
else
  IMAGE="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}@${IMAGE_MANIFEST_SHA}"
fi
echo "IMAGE $IMAGE"

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

#Check cluster availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
if [ -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
  CLUSTER_ID=${PIPELINE_KUBERNETES_CLUSTER_ID:-${PIPELINE_KUBERNETES_CLUSTER_NAME}} # use cluster id instead of cluster name to handle case where there are multiple clusters with same name
  IP_ADDR=$( ibmcloud ks workers --cluster ${CLUSTER_ID} | grep normal | head -n 1 | awk '{ print $2 }' )
  if [ -z "${IP_ADDR}" ]; then
    echo -e "${PIPELINE_KUBERNETES_CLUSTER_NAME} not created or workers not ready"
    exit 1
  fi
  # Use alternate operator .ingress.XXX for vpc/gen2 / apiv2 cluster
  CLUSTER_INGRESS_SUBDOMAIN=$( ibmcloud ks cluster get --cluster ${CLUSTER_ID} --json | jq -r '.ingressHostname // .ingress.hostname' | cut -d, -f1 )
  CLUSTER_INGRESS_SECRET=$( ibmcloud ks cluster get --cluster ${CLUSTER_ID} --json | jq -r '.ingressSecretName // .ingress.secretName' | cut -d, -f1 )
else
  CLUSTER_INGRESS_SUBDOMAIN=""
  CLUSTER_INGRESS_SECRET=""
fi
echo "Configuring cluster namespace"
if kubectl get namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace ${CLUSTER_NAMESPACE}
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

# Grant access to private image registry from namespace $CLUSTER_NAMESPACE
# reference https://cloud.ibm.com/docs/containers?topic=containers-images#other_registry_accounts
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
if [ -z "${KUBERNETES_SERVICE_ACCOUNT_NAME}" ]; then KUBERNETES_SERVICE_ACCOUNT_NAME="default" ; fi
SERVICE_ACCOUNT=$(kubectl get serviceaccount ${KUBERNETES_SERVICE_ACCOUNT_NAME}  -o json --namespace ${CLUSTER_NAMESPACE} )
if ! echo ${SERVICE_ACCOUNT} | jq -e '. | has("imagePullSecrets")' > /dev/null ; then
  kubectl patch --namespace ${CLUSTER_NAMESPACE} serviceaccount/${KUBERNETES_SERVICE_ACCOUNT_NAME} -p '{"imagePullSecrets":[{"name":"'"${IMAGE_PULL_SECRET_NAME}"'"}]}'
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

echo "=========================================================="
echo "CHECKING DEPLOYMENT.YML manifest"
if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
if [ ! -f ${DEPLOYMENT_FILE} ]; then
  echo "No ${DEPLOYMENT_FILE} found. Initializing it."
  deployment_content=$(cat <<'EOT'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: %s
spec:
  replicas: 1
  selector:
    matchLabels:
      app: %s
  template:
    metadata:
      labels:
        app: %s
    spec:
      containers:
      - name: %s
        image: %s
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: %s
---
apiVersion: v1
kind: Service
metadata:
  name: %s
  labels:
    app: %s
spec:
  type: NodePort
  ports:
    - port: %s
  selector:
    app: %s
EOT
)
  # Find the port
  PORT=$(ibmcloud cr image-inspect "${IMAGE}" --format '{{ range $key,$value := .Config.ExposedPorts }} {{ $key }} {{ "" }} {{end}}' | sed -E 's/^[^0-9]*([0-9]+).*$/\1/') || true
  if [ "$PORT" -eq "$PORT" ] 2>/dev/null; then
    echo "ExposedPort $PORT found while inspecting image ${IMAGE}"
  else 
    echo "Found '$PORT' as ExposedPort while inspecting image ${IMAGE}, non numeric value so using 5000 as containerPort"
    PORT=5000
  fi
  # Generate deployment file  
  echo "GENERATED ${DEPLOYMENT_FILE}:"
  # Derive an application name from toolchain name ensuring it is conform to DNS-1123 subdomain
  application_name=$(echo ${IDS_PROJECT_NAME:-$IMAGE_NAME} | tr -cd '[:alnum:].-')
  printf "$deployment_content" \
   "${application_name}" "${application_name}" "${application_name}" "${application_name}" "${IMAGE}" "${PORT}" \
   "${application_name}" "${application_name}" "${PORT}" "${application_name}" | tee ${DEPLOYMENT_FILE}
fi

echo "=========================================================="
echo "UPDATING manifest with image information"
echo -e "Updating ${DEPLOYMENT_FILE} with image name: ${IMAGE}"
NEW_DEPLOYMENT_FILE="$(dirname $DEPLOYMENT_FILE)/tmp.$(basename $DEPLOYMENT_FILE)"
# find the yaml document index for the K8S deployment definition
DEPLOYMENT_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="deployment") | .key')
if [ -z "$DEPLOYMENT_DOC_INDEX" ]; then
  echo "No Kubernetes Deployment definition found in $DEPLOYMENT_FILE. Updating YAML document with index 0"
  DEPLOYMENT_DOC_INDEX=0
fi
# Update deployment with image name
yq write $DEPLOYMENT_FILE --doc $DEPLOYMENT_DOC_INDEX "spec.template.spec.containers[0].image" "${IMAGE}" > ${NEW_DEPLOYMENT_FILE}
DEPLOYMENT_FILE=${NEW_DEPLOYMENT_FILE} # use modified file
cat ${DEPLOYMENT_FILE}

if [ ! -z "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; then
  echo "=========================================================="
  echo "UPDATING manifest with ingress information"
  INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
  if [ -z "$INGRESS_DOC_INDEX" ]; then
    echo "No Kubernetes Ingress definition found in $DEPLOYMENT_FILE."
  else
    # Update ingress with cluster domain/secret information
    # Look for ingress rule whith host contains the token "cluster-ingress-subdomain"
    INGRESS_RULES_INDEX=$(yq r --doc $INGRESS_DOC_INDEX --tojson $DEPLOYMENT_FILE | jq '.spec.rules | to_entries | .[] | select( .value.host | contains("cluster-ingress-subdomain")) | .key')
    if [ ! -z "$INGRESS_RULES_INDEX" ]; then
      INGRESS_RULE_HOST=$(yq r --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.rules[${INGRESS_RULES_INDEX}].host)
      yq w --inplace --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.rules[${INGRESS_RULES_INDEX}].host ${INGRESS_RULE_HOST/cluster-ingress-subdomain/$CLUSTER_INGRESS_SUBDOMAIN}
    fi
    # Look for ingress tls whith secret contains the token "cluster-ingress-secret"
    INGRESS_TLS_INDEX=$(yq r --doc $INGRESS_DOC_INDEX --tojson $DEPLOYMENT_FILE | jq '.spec.tls | to_entries | .[] | select(.secretName="cluster-ingress-secret") | .key')
    if [ ! -z "$INGRESS_TLS_INDEX" ]; then
      yq w --inplace --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}].secretName $CLUSTER_INGRESS_SECRET
      INGRESS_TLS_HOST_INDEX=$(yq r --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}] --tojson | jq '.hosts | to_entries | .[] | select( .value | contains("cluster-ingress-subdomain")) | .key')
      if [ ! -z "$INGRESS_TLS_HOST_INDEX" ]; then
        INGRESS_TLS_HOST=$(yq r --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}].hosts[$INGRESS_TLS_HOST_INDEX])
        yq w --inplace --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}].hosts[$INGRESS_TLS_HOST_INDEX] ${INGRESS_TLS_HOST/cluster-ingress-subdomain/$CLUSTER_INGRESS_SUBDOMAIN}
      fi
    fi
  fi
fi




  


