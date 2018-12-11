#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/istio_virtualservice_canary_dark.sh) and 'source' it from your pipeline job
#    source ./scripts/istio_virtualservice_canary_dark.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_virtualservice_canary_dark.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_virtualservice_canary_dark.sh

# Route all traffic to "stable" destination (using Istio)

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

if [ -z "${VIRTUAL_SERVICE_FILE}" ]; then VIRTUAL_SERVICE_FILE=istio_virtualservice_canary_dark.yaml ; fi
if [ ! -f ${VIRTUAL_SERVICE_FILE} ]; then
  if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
  if [ ! -f ${DEPLOYMENT_FILE} ]; then
      echo -e "${red}Kubernetes deployment file '${DEPLOYMENT_FILE}' not found${no_color}"
      exit 1
  fi
  # Install 'yq' to process yaml files
  python -m site &> /dev/null && export PATH="$PATH:`python -m site --user-base`/bin"
  pip install yq
  echo -e "Updating $DEPLOYMENT_FILE to represent canary deployment: add label version, modify deployment name"
  DEPLOYMENT_NAME=$( cat ${DEPLOYMENT_FILE} | yq -r '. | select(.kind=="Deployment") | .metadata.name' ) # read deployment name
  cat > ${VIRTUAL_SERVICE_FILE} << EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: virtual-service-${DEPLOYMENT_NAME}
spec:
  hosts:
    - '*'
  gateways:
    - gateway-${DEPLOYMENT_NAME}
  http:
    - match:
        - headers:
            user-agent:
              regex: '.*Firefox.*'
      route:
        - destination:
            host: ${DEPLOYMENT_NAME}
            subset: canary
    - route:
        - destination:
            host: ${DEPLOYMENT_NAME}
            subset: stable
EOF
  #sed -e "s/\${DEPLOYMENT_NAME}/${DEPLOYMENT_NAME}/g" ${VIRTUAL_SERVICE_FILE}
fi
cat ${VIRTUAL_SERVICE_FILE}
kubectl apply -f ${VIRTUAL_SERVICE_FILE} --namespace ${CLUSTER_NAMESPACE}

kubectl get gateways,destinationrules,virtualservices --namespace ${CLUSTER_NAMESPACE}

echo -e "Gateways, destination rules and virtual services in namespace: ${CLUSTER_NAMESPACE}"
kubectl get gateway,destinationrule,virtualservice --namespace ${CLUSTER_NAMESPACE}

# echo -e "Installed gateway details:"
# kubectl get gateway gateway-${DEPLOYMENT_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml

# echo -e "Installed destination rule details:"
# kubectl get destinationrule destination-rule-${DEPLOYMENT_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml

# echo -e "Installed virtual service details:"
# kubectl get virtualservice virtual-service-${DEPLOYMENT_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml
