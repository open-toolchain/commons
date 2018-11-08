#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/istio_virtualservice_canary_weight.sh) and 'source' it from your pipeline job
#    source ./scripts/istio_virtualservice_canary_weight.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_virtualservice_canary_weight.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_virtualservice_canary_weight.sh

# Route all traffic to "stable" destination (using Istio)

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "CANARY_WEIGHT=${CANARY_WEIGHT}"

if [ -z "${CANARY_WEIGHT}"]; then
  echo "Weight of canary destination not set (CANARY_WEIGHT)"
  exit 1
else
  echo -e "Adjusting weight of canary destination to: ${CANARY_WEIGHT}%"
fi
let STABLE_WEIGHT=100-${CANARY_WEIGHT}
if [ -z "${VIRTUAL_SERVICE_FILE}" ]; then VIRTUAL_SERVICE_FILE=istio_virtualservice_canary_weight.yaml ; fi
if [ ! -f ${VIRTUAL_SERVICE_FILE} ]; then
  cat > ${VIRTUAL_SERVICE_FILE} << EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: virtual-service-${IMAGE_NAME}
spec:
  hosts:
    - '*'
  gateways:
    - gateway-${IMAGE_NAME}
  http:
    - route:
        - destination:
            host: ${IMAGE_NAME}
            subset: stable
          weight: ${STABLE_WEIGHT}
        - destination:
            host: ${IMAGE_NAME}
            subset: canary
          weight: ${CANARY_WEIGHT}
EOF
    #sed -e "s/\${IMAGE_NAME}/${IMAGE_NAME}/g" ${VIRTUAL_SERVICE_FILE}
  fi
  cat ${VIRTUAL_SERVICE_FILE}
  kubectl apply -f ${VIRTUAL_SERVICE_FILE} --namespace ${CLUSTER_NAMESPACE}
fi

kubectl get gateways,destinationrules,virtualservices --namespace ${CLUSTER_NAMESPACE}