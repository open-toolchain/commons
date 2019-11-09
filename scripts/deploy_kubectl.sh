#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_kubectl.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_kubectl.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_kubectl.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_kubectl.sh

# Perform a kubectl deploy of container image and check on outcome

# Input env variables (can be received via a pipeline environment properties.file.
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "DEPLOYMENT_FILE=${DEPLOYMENT_FILE}"
echo "USE_ISTIO_GATEWAY=${USE_ISTIO_GATEWAY}"
echo "KUBERNETES_SERVICE_ACCOUNT_NAME=${KUBERNETES_SERVICE_ACCOUNT_NAME}"

echo "Use for custom Kubernetes cluster target:"
echo "KUBERNETES_MASTER_ADDRESS=${KUBERNETES_MASTER_ADDRESS}"
echo "KUBERNETES_MASTER_PORT=${KUBERNETES_MASTER_PORT}"
echo "KUBERNETES_SERVICE_ACCOUNT_TOKEN=${KUBERNETES_SERVICE_ACCOUNT_TOKEN}"


#View build properties
# cat build.properties
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://cloud.ibm.com/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
if [ -z "${CLUSTER_NAMESPACE}" ]; then CLUSTER_NAMESPACE=default ; fi
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

# If custom cluster credentials available, connect to this cluster instead
if [ ! -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
  kubectl config set-cluster custom-cluster --server=https://${KUBERNETES_MASTER_ADDRESS}:${KUBERNETES_MASTER_PORT} --insecure-skip-tls-verify=true
  kubectl config set-credentials sa-user --token="${KUBERNETES_SERVICE_ACCOUNT_TOKEN}"
  kubectl config set-context custom-context --cluster=custom-cluster --user=sa-user --namespace="${CLUSTER_NAMESPACE}"
  kubectl config use-context custom-context
fi
kubectl cluster-info

echo "=========================================================="
echo "DEPLOYING using manifest"
echo -e "Updating ${DEPLOYMENT_FILE} with image name: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"
if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
if [ -f ${DEPLOYMENT_FILE} ]; then
    sed -i "s~^\([[:blank:]]*\)image:.*$~\1image: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}~" ${DEPLOYMENT_FILE}
    cat ${DEPLOYMENT_FILE}
else 
  echo "No ${DEPLOYMENT_FILE} found. Initializing it."
  deployment_content=$(cat <<'EOT'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: %s
spec:
  replicas: 1
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
  PORT=$(ibmcloud cr image-inspect "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}" --format '{{ range $key,$value := .ContainerConfig.ExposedPorts }} {{ $key }} {{ "" }} {{end}}' | sed -E 's/^[^0-9]*([0-9]+).*$/\1/') || true
  if [ "$PORT" -eq "$PORT" ] 2>/dev/null; then
    echo "ExposedPort $PORT found while inspecting image ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"
  else 
    echo "Found '$PORT' as ExposedPort while inspecting image ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}, non numeric value so using 5000 as containerPort"
    PORT=5000
  fi
  # Generate deployment file  
  echo "GENERATED ${DEPLOYMENT_FILE}:"
  # Derive an application name from toolchain name ensuring it is conform to DNS-1123 subdomain
  application_name=$(echo ${IDS_PROJECT_NAME} | tr -cd '[:alnum:].-')
  printf "$deployment_content" \
   "${application_name}" "${application_name}" "${application_name}" "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}" "${PORT}" \
   "${application_name}" "${application_name}" "${PORT}" "${application_name}" | tee ${DEPLOYMENT_FILE}
fi    
set -x
# if [ "${USE_ISTIO_GATEWAY}" = true ]; then
#   echo -e "Istio not found, installing it..."
#   WORKING_DIR=$(pwd)
#   mkdir ~/tmpbin && cd ~/tmpbin
#   curl -L https://git.io/getLatestIstio | sh -
#   ISTIO_ROOT=$(pwd)/$(find istio-* -maxdepth 0 -type d)
#   export PATH=${ISTIO_ROOT}/bin:$PATH
#   cd $WORKING_DIR
#   kubectl apply --namespace ${CLUSTER_NAMESPACE} -f <(istioctl kube-inject -f ${DEPLOYMENT_FILE})
# else
kubectl apply --namespace ${CLUSTER_NAMESPACE} -f ${DEPLOYMENT_FILE}
# fi
set +x

echo ""
echo "=========================================================="
IMAGE_REPOSITORY=${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}
echo -e "CHECKING deployment status of ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
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
    echo "Please check proper authenticating to from cluster to image registry (e.g. image pull secret)"
    break; # no need to wait longer, error is fatal
  elif [[ ${REASON} == *CrashLoopBackOff* ]]; then
    echo "Detected CrashLoopBackOff failure. "
    echo "Application is unable to start, check the application startup logs"
    break; # no need to wait longer, error is fatal
  fi
  sleep 5
done

#echo "Application Logs"
#kubectl logs --selector app=${APP_NAME} --namespace ${CLUSTER_NAMESPACE}  
echo ""
if [[ ! -z "$NOT_READY" ]]; then
  echo ""
  echo "=========================================================="
  echo "DEPLOYMENT FAILED"
  exit 1
fi

echo "=========================================================="
APP_NAME=$(kubectl get pods --namespace ${CLUSTER_NAMESPACE} -o json | jq -r '[ .items[] | select(.spec.containers[]?.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") | .metadata.labels.app] [1]')
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
  echo ""
  if [ -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
    IP_ADDR=$( bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | head -n 1 | awk '{ print $2 }' )
    if [ -z "${IP_ADDR}" ]; then
      echo -e "${PIPELINE_KUBERNETES_CLUSTER_NAME} not created or workers not ready"
      exit 1
    fi
  else
    IP_ADDR=${KUBERNETES_MASTER_ADDRESS}
  fi  
  if [ "${USE_ISTIO_GATEWAY}" = true ]; then
    PORT=$( kubectl get svc istio-ingressgateway -n istio-system -o json | jq -r '.spec.ports[] | select (.name=="http2") | .nodePort ' )
    echo -e "*** istio gateway enabled ***"
  else
    PORT=$( kubectl get services --namespace ${CLUSTER_NAMESPACE} | grep ${APP_SERVICE} | sed 's/.*:\([0-9]*\).*/\1/g' )
  fi
  export APP_URL=http://${IP_ADDR}:${PORT} # using 'export', the env var gets passed to next job in stage
  echo -e "VIEW THE APPLICATION AT: ${APP_URL}"
fi
