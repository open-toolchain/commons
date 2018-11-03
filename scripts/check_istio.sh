#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_istio.sh) and 'source' it from your pipeline job
#    source ./scripts/check_istio.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_istio.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_istio.sh

# Install ISTIO in target cluster, and wait for ready state

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"

ISTIO_NAMESPACE=istio-system
echo "Checking Istio configuration"
if kubectl get namespace ${ISTIO_NAMESPACE}; then
  echo -e "Namespace ${ISTIO_NAMESPACE} found."
else
  echo -e "Istio not found, installing it..."
  WORKING_DIR=$(pwd)
  mkdir ~/tmpbin && cd ~/tmpbin
  curl -L https://git.io/getLatestIstio | sh -
  ISTIO_ROOT=$(pwd)/$(find istio* -maxdepth 0 -type d)
  export PATH=${ISTIO_ROOT}/bin:$PATH
  cd $WORKING_DIR

  kubectl apply -f ${ISTIO_ROOT}/install/kubernetes/istio-demo.yaml
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
    echo $DATA | jq '.items[].status.containerStatuses?[] | select(.ready==true or .state.terminated != null) ' 
    break # deployment succeeded
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
  exit 1
fi

kubectl api-resources