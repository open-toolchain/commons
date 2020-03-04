#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/istio_check_install.sh) and 'source' it from your pipeline job
#    source ./scripts/istio_check_install.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_check_install.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/istio_check_install.sh

# Check ISTIO installation in target cluster

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "DEFAULT_ISTIO_VERSION=${DEFAULT_ISTIO_VERSION}"

ISTIO_NAMESPACE=istio-system
echo "Checking Istio configuration"
if kubectl get namespace ${ISTIO_NAMESPACE}; then
  echo -e "Namespace ${ISTIO_NAMESPACE} found."
else
  echo "Istio not found, installing the Managed Istio add-on in the Kubernetes Cluster ! "
  ibmcloud ks cluster addon enable istio --cluster ${PIPELINE_KUBERNETES_CLUSTER_NAME}

  # Alternative commands for installing a custom Istio version (DEFAULT_ISTIO_VERSION)
  # Reminder: Istio 1.0 is deprecated (https://istio.io/blog/2019/announcing-1.0-eol/), be aware you'll need a STANDARD cluster to run recent versions of Istio >1.1 ."
  # echo -e "Proceeding with installing custom version: ${DEFAULT_ISTIO_VERSION}"
  # WORKING_DIR=$(pwd)
  # mkdir ~/tmpbin && cd ~/tmpbin
  # ISTIO_VERSION=${DEFAULT_ISTIO_VERSION}
  # curl -L https://git.io/getLatestIstio | sh - 
  # ISTIO_ROOT=$(pwd)/$(find istio-* -maxdepth 0 -type d)
  # export PATH=${ISTIO_ROOT}/bin:$PATH
  # cd $WORKING_DIR
  # kubectl apply -f ${ISTIO_ROOT}/install/kubernetes/istio-demo.yaml
fi

echo ""
echo "=========================================================="
echo -e "CHECKING installation status of ISTIO"
echo ""
for ITERATION in {1..30}
do
  DATA=$( kubectl get pods --namespace ${ISTIO_NAMESPACE} -o json )
  NOT_READY=$(echo $DATA | jq '.items[].status | select(.containerStatuses!=null) | .containerStatuses[] | select(.ready==false and .state.terminated==null)')
  if [[ -z "$NOT_READY" ]]; then
    echo -e "All pods are ready:"
    break # istio installation succeeded
  fi
  echo -e "${ITERATION} : Deployment still pending..."
  echo -e "NOT_READY:${NOT_READY}"
  sleep 5
done

if [[ ! -z "$NOT_READY" ]]; then
  echo ""
  echo "=========================================================="
  echo "ISTIO INSTALLATION CHECK : FAILED"
  echo "Please check that the target cluster meets the Istio system requirements (e.g. LITE clusters do not have enough capacity)."
  exit 1
fi

# kubectl api-resources
