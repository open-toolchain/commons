#!/bin/bash

IBMCLOUD_API_KEY=${PIPELINE_BLUEMIX_API_KEY}

function createAndDeploySatelliteConfig() {

echo "=========================================================="
SAT_CONFIG=$1
SAT_CONFIG_VERSION=$2
KUBE_RESOURCE=$3
DEPLOY_FILE=$4
echo "Creating config for $SAT_CONFIG...."

export SATELLITE_SUBSCRIPTION="$SAT_CONFIG-$SATELLITE_CLUSTER_GROUP"
export SAT_CONFIG_VERSION
if ! ic sat config version get --config "$SAT_CONFIG" --version "$SAT_CONFIG_VERSION" &>/dev/null; then
  echo -e "Current resource ${KUBE_RESOURCE} not found in ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}, creating it"
  if ! ibmcloud sat config get --config "$SAT_CONFIG" &>/dev/null ; then
    ibmcloud sat config create --name "$SAT_CONFIG"
  fi
  echo "deployment file is ${DEPLOY_FILE}"
  ibmcloud sat config version create --name "$SAT_CONFIG_VERSION" --config "$SAT_CONFIG" --file-format yaml --read-config ${DEPLOY_FILE}
else
  echo -e "Current resource ${KUBE_RESOURCE} already found in ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"
fi

EXISTING_SUB=$(ibmcloud sat subscription ls -q | grep "$SATELLITE_SUBSCRIPTION" || true)
  if [ -z "${EXISTING_SUB}" ]; then
    ibmcloud sat subscription create --name "$SATELLITE_SUBSCRIPTION" --group "$SATELLITE_CLUSTER_GROUP" --version "$SAT_CONFIG_VERSION" --config "$SAT_CONFIG"
  else
    ibmcloud sat subscription update --subscription "$SATELLITE_SUBSCRIPTION" -f --group "$SATELLITE_CLUSTER_GROUP" --version "$SAT_CONFIG_VERSION"
fi

}


echo "=========================================================="
echo "Creating NameSpace...."
export SATELLITE_CONFIG_NAMESPACE="${APP_NAME}-${IBMCLOUD_IKS_CLUSTER_NAMESPACE}-namespace-${IBMCLOUD_TOOLCHAIN_ID}"
NAMESPACE_FILE="${SATELLITE_CONFIG_NAMESPACE}.yaml"    
cat > "${NAMESPACE_FILE}" << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}
  labels:
    razee/watch-resource: lite 
EOF
cat "${NAMESPACE_FILE}"
NAMESPACE_SHA256=$(cat "${NAMESPACE_FILE}" | sha256sum)
echo "NameSpace SHA256: ${NAMESPACE_SHA256}"

createAndDeploySatelliteConfig "${SATELLITE_CONFIG_NAMESPACE}" "${NAMESPACE_SHA256}" "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}" "${NAMESPACE_FILE}"
echo "=========================================================="

echo "=========================================================="
echo -e "CONFIGURING ACCESS to private image registry from namespace ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"
KUBERNETES_SERVICE_ACCOUNT_NAME="${APP_NAME}-${IBMCLOUD_TOOLCHAIN_ID}-sa"
IMAGE_PULL_SECRET_NAME="${APP_NAME}-pullsecret-${REGISTRY_URL}"


echo "Creating Service Account...."
export SATELLITE_CONFIG_ACCOUNT="${APP_NAME}-${IBMCLOUD_IKS_CLUSTER_NAMESPACE}-service-account-${IBMCLOUD_TOOLCHAIN_ID}"
export REGISTRY_AUTH=$(echo "{\"auths\":{\"${REGISTRY_URL}\":{\"auth\":\"$(echo -n iamapikey:${IBMCLOUD_API_KEY} | base64 -w 0)\",\"username\":\"iamapikey\",\"email\":\"iamapikey\",\"password\":\"${IBMCLOUD_API_KEY}\"}}}" | base64 -w 0)
echo "REGISTRY_AUTH=${REGISTRY_AUTH}"
ACCOUNT_FILE="${SATELLITE_CONFIG_ACCOUNT}.yaml"    
cat > "${ACCOUNT_FILE}" << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${KUBERNETES_SERVICE_ACCOUNT_NAME}
  namespace: ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}
  labels:
    razee/watch-resource: lite  
imagePullSecrets:
  - name: ${IMAGE_PULL_SECRET_NAME}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${IMAGE_PULL_SECRET_NAME}
  namespace: ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}
  labels:
    razee/watch-resource: lite  
data:
  .dockerconfigjson: ${REGISTRY_AUTH}
type: kubernetes.io/dockerconfigjson
EOF

IMAGE_PULL_SECRET_SHA256=$(cat "${ACCOUNT_FILE}" | sha256sum)
echo "Image pull secret SHA256: ${IMAGE_PULL_SECRET_SHA256}"

createAndDeploySatelliteConfig "${SATELLITE_CONFIG_ACCOUNT}" "${IMAGE_PULL_SECRET_SHA256}" "IMAGEPULLSECRET" "${ACCOUNT_FILE}"
echo "=========================================================="


echo "UPDATING manifest with image information"
echo -e "Updating ${DEPLOYMENT_FILE} with image name: ${IMAGE}@${IMAGE_MANIFEST_SHA}"
NEW_DEPLOYMENT_FILE="$(dirname $DEPLOYMENT_FILE)/tmp.$(basename $DEPLOYMENT_FILE)"

cp ${DEPLOYMENT_FILE} ${NEW_DEPLOYMENT_FILE}
DEPLOYMENT_FILE=${NEW_DEPLOYMENT_FILE}

echo -e "Updating ${DEPLOYMENT_FILE} with namespace: ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"
yq write --inplace $DEPLOYMENT_FILE --doc "*" "metadata.namespace" "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"


echo -e "Updating ${DEPLOYMENT_FILE} with traceability label: metadata.labels.razee/watch-resource"
yq write --inplace $DEPLOYMENT_FILE --doc "*" "metadata.labels.razee/watch-resource" "lite" 

echo -e "Updating ${DEPLOYMENT_FILE} with namespace: ${SERVICE_ACCOUNT}"
yq write --inplace $DEPLOYMENT_FILE --doc "*" "spec.template.spec.serviceAccountName" "${KUBERNETES_SERVICE_ACCOUNT_NAME}"


echo "=========================================================="
echo "DEPLOYING using SATELLITE CONFIG"



if [ -z "${SATELLITE_CONFIG}" ]; then
  export SATELLITE_CONFIG="${APP_NAME}-${IBMCLOUD_IKS_CLUSTER_NAMESPACE}-resources-${IBMCLOUD_TOOLCHAIN_ID}"
fi
if [ -z "${SATELLITE_SUBSCRIPTION}" ]; then
  export SATELLITE_SUBSCRIPTION="${SATELLITE_CONFIG}-${SATELLITE_CLUSTER_GROUP}"
fi
if [ -z "${SATELLITE_CONFIG_VERSION}" ]; then
  export SATELLITE_CONFIG_VERSION="$BUILD_NUMBER-"$(date -u "+%Y%m%d%H%M%S") 
fi

createAndDeploySatelliteConfig "${SATELLITE_CONFIG}" "${SATELLITE_CONFIG_VERSION}" "APPDEPLOYMENT" "${DEPLOYMENT_FILE}"

echo -e "Checking deployment rollout status"
GROUP_SIZE=$( ic sat group get --group $SATELLITE_CLUSTER_GROUP --output json | jq '.clusters | length' )
for ITER in {1..30}
do
  SAT_OUTPUT=$( ibmcloud sat subscription get --subscription ${SATELLITE_SUBSCRIPTION} --output json )
  SUCCESS_COUNT=$( echo ${SAT_OUTPUT} | jq .subscription.rolloutStatus.successCount )
  if [ -z "$SUCCESS_COUNT" ]; then SUCCESS_COUNT=0; fi
  ERROR_COUNT=$( echo ${SAT_OUTPUT} | jq .subscription.rolloutStatus.errorCount )
  if [ -z "$ERROR_COUNT" ]; then ERROR_COUNT=0; fi
  if [[ ${ERROR_COUNT} > 0 ]]; then
    STATUS="ERROR"
  else
    STATUS="PENDING"
  fi
  echo -e "${ITER} STATUS : succeeded=${SUCCESS_COUNT} - failed=${ERROR_COUNT} ."
  if [[ $(( SUCCESS_COUNT + ERROR_COUNT )) == ${GROUP_SIZE} ]]; then
    break
  fi
  echo "Waiting for all deployments to complete..."
  sleep 10
done


ibmcloud sat subscription get --subscription ${SATELLITE_SUBSCRIPTION}
if [[ ${ERROR_COUNT} > 0 ]]; then
  echo "DEPLOYMENT FAILED"
  echo ""
  SATELLITE_CONFIG_ID=$( ibmcloud sat config get --config "${SATELLITE_CONFIG}" --output json | jq -r .uuid )
  echo "Please check details at https://cloud.ibm.com/satellite/configuration/${SATELLITE_CONFIG_ID}/overview"
  exit 1
fi
