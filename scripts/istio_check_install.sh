#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_istio.sh) and 'source' it from your pipeline job
#    source ./scripts/check_istio.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_istio.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_istio.sh

# Check ISTIO installation in target cluster

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"

ISTIO_NAMESPACE=istio-system
echo "Checking Istio configuration"
if kubectl get namespace ${ISTIO_NAMESPACE}; then
  echo -e "Namespace ${ISTIO_NAMESPACE} found."
else
  echo "ISTIO NOT FOUND ! Please enable the Managed Istio add-on for this cluster."
  exit 1
fi

echo ""
echo "=========================================================="
echo -e "CHECKING deployment status of ISTIO"
echo ""
for ITERATION in {1..30}
do
  DATA=$( kubectl get pods --namespace ${ISTIO_NAMESPACE} -o json )
  NOT_READY=$(echo $DATA | jq '.items[].status.containerStatuses?[] | select(.ready==false and .state.terminated == null) ')
  if [[ -z "$NOT_READY" ]]; then
    echo -e "All pods are ready:"
    # echo $DATA | jq '.items[].status.containerStatuses?[] | select(.ready==false or .state.terminated != null) ' 
    break # istio installation succeeded
  fi
  REASON=$(echo $DATA | jq '.items[].status.containerStatuses?[] | .state.waiting.reason')
  echo -e "${ITERATION} : Deployment still pending..."
  echo -e "NOT_READY:${NOT_READY}"
  echo -e "REASON: ${REASON}"
  sleep 5
done

if [[ ! -z "$NOT_READY" ]]; then
  echo ""
  echo "=========================================================="
  echo "ISTIO INSTALLATION FAILED"
  echo ""
  echo "Note: Latest Istio requirements do exceed the resources of a lite cluster, recommending to use a standard clusteer with sufficient capacity and the managed Istio add-on."
  exit 1
fi

# kubectl api-resources