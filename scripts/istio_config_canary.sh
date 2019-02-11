#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/config_istio_canary.sh) and 'source' it from your pipeline job
#    source ./scripts/config_istio_canary.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/config_istio_canary.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/config_istio_canary.sh

# Configure Istio gateway with a destination rule (stable/canary), and virtual service

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "DEPLOYMENT_FILE=${DEPLOYMENT_FILE}"

#Check namespace availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
if kubectl get namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace ${CLUSTER_NAMESPACE}
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

echo "=========================================================="
echo "CHECK SIDECAR is automatically injected"
AUTO_SIDECAR_INJECTION=$(kubectl get namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.metadata.labels."istio-injection"')
if [ "${AUTO_SIDECAR_INJECTION}" == "enabled" ]; then
    echo "Automatic Istio sidecar injection already enabled"
else
    # https://istio.io/docs/setup/kubernetes/sidecar-injection/#automatic-sidecar-injection
    kubectl label namespace ${CLUSTER_NAMESPACE} istio-injection=enabled
    echo "Automatic Istio sidecar injection now enabled"
    kubectl get namespace ${CLUSTER_NAMESPACE} -L istio-injection
fi

echo "=========================================================="
echo "CONFIGURE GATEWAY with 2 subsets 'stable' and 'canary'. Initially routing all traffic to 'stable' subset".
if [ -z "${GATEWAY_FILE}" ]; then GATEWAY_FILE=istio_gateway.yaml ; fi
if [ ! -f ${GATEWAY_FILE} ]; then
  echo -e "Inferring gateway configuration using Kubernetes deployment yaml file : ${DEPLOYMENT_FILE}"
  if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
  if [ ! -f ${DEPLOYMENT_FILE} ]; then
      echo -e "${red}Kubernetes deployment file '${DEPLOYMENT_FILE}' not found${no_color}"
      exit 1
  fi
  # Install 'yq' to process yaml files
  python -m site &> /dev/null && export PATH="$PATH:`python -m site --user-base`/bin"
  pip install yq
  # read app name if present, if not default to deployment name
  APP_NAME=$( cat ${DEPLOYMENT_FILE} | yq -r '. | select(.kind=="Deployment") | if (.metadata.labels.app) then .metadata.labels.app else .metadata.name end' ) # read deployment name
  cat > ${GATEWAY_FILE} << EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: gateway-${APP_NAME}
spec:
  selector:
    istio: ingressgateway # use istio default controller
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: destination-rule-${APP_NAME}
spec:
  host: ${APP_NAME}
  subsets:
  - name: stable
    labels:
      version: stable
  - name: canary
    labels:
      version: canary
---
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
EOF
  #sed -e "s/\${APP_NAME}/${APP_NAME}/g" ${GATEWAY_FILE}
fi
cat ${GATEWAY_FILE}
kubectl apply -f ${GATEWAY_FILE} --namespace ${CLUSTER_NAMESPACE}

# echo -e "Gateways, destination rules and virtual services in namespace: ${CLUSTER_NAMESPACE}"
# kubectl get gateway,destinationrule,virtualservice --namespace ${CLUSTER_NAMESPACE}

# echo -e "Installed gateway details:"
# kubectl get gateway gateway-${APP_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml

# echo -e "Installed destination rule details:"
# kubectl get destinationrule destination-rule-${APP_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml

# echo -e "Installed virtual service details:"
# kubectl get virtualservice virtual-service-${APP_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml

