#!/bin/bash
# uncomment to debug the script
# set -x

# This script checks the IBM Container Service cluster has Helm ready.
# That is configures Helm Tiller service to later perform a deploy with Helm.

echo "=========================================================="
echo "CHECKING HELM VERSION: matching Helm Tiller (server) if detected. "
set +e
LOCAL_VERSION=$( helm version --client | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
TILLER_VERSION=$( helm version --server | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
set -e
if [ -z "${TILLER_VERSION}" ]; then
  if [ -z "${DEFAULT_DEFAULT_HELM_VERSION}" ]; then
    CLIENT_VERSION=${DEFAULT_HELM_VERSION}
  else
    CLIENT_VERSION=${LOCAL_VERSION}
  fi
else
  echo -e "Helm Tiller ${TILLER_VERSION} already installed in cluster. Keeping it, and aligning client."
  CLIENT_VERSION=${TILLER_VERSION}
fi
if [ "${CLIENT_VERSION}" != "${LOCAL_VERSION}" ]; then
  echo -e "Installing Helm client ${CLIENT_VERSION}"
  WORKING_DIR=$(pwd)
  mkdir ~/tmpbin && cd ~/tmpbin
  curl -L https://storage.googleapis.com/kubernetes-helm/helm-v${CLIENT_VERSION}-linux-amd64.tar.gz -o helm.tar.gz && tar -xzvf helm.tar.gz
  cd linux-amd64
  export PATH=$(pwd):$PATH
  cd $WORKING_DIR
fi
if [ -z "${TILLER_VERSION}" ]; then
    echo -e "Installing Helm Tiller ${CLIENT_VERSION} with cluster admin privileges (RBAC)"
    kubectl -n kube-system create serviceaccount tiller
    kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
    helm init --service-account tiller
    # helm init --upgrade --force-upgrade
    kubectl --namespace=kube-system rollout status deploy/tiller-deploy
    # kubectl rollout status -w deployment/tiller-deploy --namespace=kube-system
fi
helm version
helm init
