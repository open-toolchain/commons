#!/bin/bash
# This script checks the IBM Container Service cluster is ready, has a namespace configured with access to the private
# image registry (using an IBM Cloud API Key), perform a kubectl deploy of container image and check on outcome.
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_and_deploy_kubectl.sh) and 'source' it from your pipeline job
#    source ./scripts/check_and_deploy_kubectl.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_and_deploy_kubectl.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_and_deploy_kubectl.sh

# This script checks the IBM Container Service cluster is ready, has a namespace configured with access to the private
# image registry (using an IBM Cloud API Key), perform a kubectl deploy of container image and check on outcome.

# Input env variables (can be received via a pipeline environment properties.file.

echo "Installing Updated version of IBM Cloud CLI...."
curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
ibmcloud  plugin install  kubernetes-service -f

ic plugin list
ic plugin update kubernetes-service -f


if [ -z "${IMAGE_MANIFEST_SHA}" ]; then
  IMAGE="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"
else
  IMAGE="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}@${IMAGE_MANIFEST_SHA}"
fi
echo "IMAGE $IMAGE"

function AddDefaultIngressToDeployment() {
   deployment_content=$(cat << EOT
---   
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${CIP_SERVICE_NAME}-ingress
spec:
  defaultBackend:
    service:
        name: ${CIP_SERVICE_NAME}
        port:
          number: ${CIP_SERVICE_PORT}         
EOT
)
echo "${deployment_content}" >> "${DEPLOYMENT_FILE}"

}


function AddDefaultRouteToDeployment() {
  deployment_content=$(cat << EOT
---  
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${CIP_SERVICE_NAME}-route
spec:
  path: /
  to:
    kind: Service
    name: ${CIP_SERVICE_NAME}
  port:
    targetPort: ${CIP_SERVICE_PORT} 

EOT
)
echo "${deployment_content}" >> "${DEPLOYMENT_FILE}"

}


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


echo "=========================================================="
echo "CHECKING DEPLOYMENT.YML manifest"
if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
if [ ! -f ${DEPLOYMENT_FILE} ]; then
  echo "No ${DEPLOYMENT_FILE} found. Generating deployment..."
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
echo "Updating manifest with image information"
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

echo "Updating the Ingress with default Backend.... "
INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
if [ -z "$INGRESS_DOC_INDEX" ]; then
  echo "No Kubernetes Ingress definition found in $DEPLOYMENT_FILE."
else
  echo "Removing Ingress definition from the deployment file."
  yq delete $DEPLOYMENT_FILE --inplace  --doc $INGRESS_DOC_INDEX '*' > /dev/null 2>&1 || true
fi

export CIP_SERVICE_NAME=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Service" and .spec.type == "ClusterIP").metadata.name')
export CIP_SERVICE_PORT=$(yq r  --doc "*" ${DEPLOYMENT_FILE}  --tojson  | jq -r '.[] | select(.kind == "Service" and .spec.type == "ClusterIP").spec.ports[0].targetPort')

echo "Adding default Ingress definition in the deployment file."
AddDefaultIngressToDeployment

CLUSTERNAME=$(ibmcloud sat group get --group "${SATELLITE_CLUSTER_GROUP}" -output json | jq -r '.clusters[0].registration.name')
CLUSTERVERSION=$(ibmcloud sat cluster ls --output json | jq ".clusterSearch[] | select(.metadata.name==\"$CLUSTERNAME\") | .metadata.kube_version.gitVersion")

if [[ $CLUSTERVERSION =~ "IKS" ]]; then
   echo "This is an IKS Cluster. Skippping OpenShift Routes."
else 
  echo "Adding default Openshift Routes definition in the deployment file."
  AddDefaultRouteToDeployment
fi


