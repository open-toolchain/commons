#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/istio_virtualservice_canary_weight.sh) and 'source' it from your pipeline job
#    source ./scripts/istio_virtualservice_canary_weight.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_virtualservice_canary_weight.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_virtualservice_canary_weight.sh

# Route a fraction of traffic to "canary" destination (CANARY_WEIGHT), and rest to "stable" destination (using Istio)

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "CANARY_WEIGHT=${CANARY_WEIGHT}"
echo "DEPLOYMENT_FILE=${DEPLOYMENT_FILE}"

if [ -z "${CANARY_WEIGHT}" ]; then
  echo "Weight of canary destination not set (CANARY_WEIGHT)"
  exit 1
else
  echo -e "Adjusting weight of canary destination to: ${CANARY_WEIGHT}%"
fi
let STABLE_WEIGHT=100-${CANARY_WEIGHT}
if [ -z "${VIRTUAL_SERVICE_FILE}" ]; then VIRTUAL_SERVICE_FILE=istio_virtualservice_canary_weight.yaml ; fi
if [ ! -f ${VIRTUAL_SERVICE_FILE} ]; then
  echo -e "Inferring virtual service configuration using Kubernetes deployment yaml file : ${DEPLOYMENT_FILE}"
  if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
  if [ ! -f ${DEPLOYMENT_FILE} ]; then
      echo -e "${red}Kubernetes deployment file '${DEPLOYMENT_FILE}' not found${no_color}"
      exit 1
  fi
  # read app name if present, if not default to deployment name
  APP_NAME=$( cat ${DEPLOYMENT_FILE} | yq -r '. | select(.kind=="Deployment") | if (.metadata.labels.app) then .metadata.labels.app else .metadata.name end' ) # read deployment name  
  cat > ${VIRTUAL_SERVICE_FILE} << EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: virtual-service-${APP_NAME}
spec:
  hosts:
    - '*'
  gateways:
    - gateway-${APP_NAME}
  http:
    - route:
        - destination:
            host: ${APP_NAME}
            subset: stable
          weight: ${STABLE_WEIGHT}
        - destination:
            host: ${APP_NAME}
            subset: canary
          weight: ${CANARY_WEIGHT}
EOF
  #sed -e "s/\${APP_NAME}/${APP_NAME}/g" ${VIRTUAL_SERVICE_FILE}
fi
cat ${VIRTUAL_SERVICE_FILE}
kubectl apply -f ${VIRTUAL_SERVICE_FILE} --namespace ${CLUSTER_NAMESPACE}

kubectl get gateways,destinationrules,virtualservices --namespace ${CLUSTER_NAMESPACE}

# echo -e "Installed gateway details:"
# kubectl get gateway gateway-${APP_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml

# echo -e "Installed destination rule details:"
# kubectl get destinationrule destination-rule-${APP_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml

# echo -e "Installed virtual service details:"
# kubectl get virtualservice virtual-service-${APP_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml