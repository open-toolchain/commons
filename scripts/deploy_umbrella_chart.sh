#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_umbrella_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_helm.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_umbrella_chart.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_umbrella_chart.sh

# Performs deployment of a Helm umbrella chart, checking all components were successfully deployed
# and feeds deployment information for all components to DevOps Insights

# Input env variables (can be received via a pipeline environment properties.file.
echo "CHART_PATH=${CHART_PATH}"
echo "IMAGE_NAME=${IMAGE_NAME}" # TODO improve into RELEASE NAME
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "PIPELINE_STAGE_INPUT_REV=${PIPELINE_STAGE_INPUT_REV}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "LOGICAL_ENV_NAME=${LOGICAL_ENV_NAME}"
echo "IBM_CLOUD_API_KEY=${IBM_CLOUD_API_KEY}"

echo "build.properties:"
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

# Infer CHART_NAME from path to chart (last segment per construction for valid charts)
CHART_NAME=$(basename $CHART_PATH)

echo "=========================================================="
echo "DEFINE RELEASE by prefixing image (app) name with namespace if not 'default' as Helm needs unique release names across namespaces"
if [[ "${CLUSTER_NAMESPACE}" != "default" ]]; then
  RELEASE_NAME="${CLUSTER_NAMESPACE}-${IMAGE_NAME}"
else
  RELEASE_NAME=${IMAGE_NAME}
fi
echo -e "Release name: ${RELEASE_NAME}"

echo "=========================================================="
echo "CHECKING HELM CLIENT VERSION: matching Helm Tiller (server) if detected. "
set +e
LOCAL_VERSION=$( helm version --client | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
TILLER_VERSION=$( helm version --server | grep SemVer: | sed "s/^.*SemVer:\"v\([0-9.]*\).*/\1/" )
set -e
if [ -z "${TILLER_VERSION}" ]; then
  if [ -z "${HELM_VERSION}" ]; then
    CLIENT_VERSION=${LOCAL_VERSION}
  else
    CLIENT_VERSION=${HELM_VERSION}
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
helm version --client

echo "=========================================================="
echo "DEPLOYING HELM chart"
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

# Using 'upgrade --install" for rolling updates. Note that subsequent updates will occur in the same namespace the release is currently deployed in, ignoring the explicit--namespace argument".
echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade --install --debug --dry-run ${RELEASE_NAME} ${CHART_PATH} --set global.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade  --install ${RELEASE_NAME} ${CHART_PATH} --set global.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/wait_deploy_umbrella.sh")

echo ""
echo "=========================================================="
echo "DEPLOYMENT SUCCEEDED"
echo ""
echo -e "Status for release:${RELEASE_NAME}"
helm status ${RELEASE_NAME}

echo ""
echo -e "History for release:${RELEASE_NAME}"
helm history ${RELEASE_NAME}

# echo ""
# echo "Deployed Services:"
# kubectl describe services ${RELEASE_NAME}-${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}
# echo ""
# echo "Deployed Pods:"
# kubectl describe pods --selector app=${CHART_NAME} --namespace ${CLUSTER_NAMESPACE}

echo ""
echo -e "Updating Insights deployment records:${RELEASE_NAME}"
if [[ ! -d ${CHART_PATH}/insights ]]; then
  echo "Cannot find Insights config information in ${CHART_PATH}/insights folder"
else
  # get the deployment result from helm status command
  STATUS=$( helm status ${RELEASE_NAME} | grep STATUS: | awk '{print $2}' )
  if [[ $STATUS -eq 'DEPLOYED' ]]; then
      STATUS='pass'
  else
      STATUS='fail'
  fi

echo "Note: this script has been updated to use ibmcloud doi plugin - iDRA being deprecated"
echo "iDRA based version of this script is located at: https://github.com/open-toolchain/commons/blob/v1.0.idra_based/scripts/deploy_umbrella_chart.sh"

  # If APP_NAME is defined then create a deployment record the umbrella chart deployment
  if [ "$APP_NAME" ]; then
    ibmcloud doi publishdeployrecord --logicalappname="${APP_NAME}" --buildnumber=${SOURCE_BUILD_NUMBER} --env=${LOGICAL_ENV_NAME} --status=${STATUS}
  fi

  # Keep the current APP_NAME and SOURCE_BUILD_NUMBER to restore it after sub-component DOI deployment record
  PREVIOUS_APP_NAME=$APP_NAME
  PREVIOUS_SOURCE_BUILD_NUMBER=$SOURCE_BUILD_NUMBER

  ls ${CHART_PATH}/insights/*
  echo "LOGICAL_ENV_NAME=${LOGICAL_ENV_NAME}"
  for INSIGHT_CONFIG in $( ls -v ${CHART_PATH}/insights); do
    echo -e "Publish deploy record for component: ${INSIGHT_CONFIG}"
    APP_NAME=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep APP_NAME | cut -d'=' -f2 )
    GIT_BRANCH=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep GIT_BRANCH | cut -d'=' -f2 )
    SOURCE_BUILD_NUMBER=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep SOURCE_BUILD_NUMBER | cut -d'=' -f2 )
 
    echo -e "APP_NAME: ${APP_NAME}"
    echo -e "GIT_BRANCH: ${GIT_BRANCH}"
    echo -e "SOURCE_BUILD_NUMBER: ${SOURCE_BUILD_NUMBER}"

    # publish deploy records for each microservice
    ibmcloud doi publishdeployrecord --logicalappname="${APP_NAME}" --buildnumber=${SOURCE_BUILD_NUMBER} --env=${LOGICAL_ENV_NAME} --status=${STATUS}

    # get the process exit code
    RESULT=$?  
    if [[ ${RESULT} != 0 ]]; then
        exit ${RESULT}
    fi
  done
fi

# Restore APP_NAME and SOURCE_BUILD_NUMBER after sub-component DOI deployment record
export APP_NAME=$PREVIOUS_APP_NAME
export SOURCE_BUILD_NUMBER=$PREVIOUS_SOURCE_BUILD_NUMBER

echo "=========================================================="
CLUSTER_ID=${PIPELINE_KUBERNETES_CLUSTER_ID:-${PIPELINE_KUBERNETES_CLUSTER_NAME}} # use cluster id instead of cluster name to handle case where there are multiple clusters with same name
IP_ADDR=$( ibmcloud ks workers --cluster ${CLUSTER_ID} | grep normal | head -n 1 | awk '{ print $2 }' )

echo -e "Deployed services:"
kubectl get services --namespace ${CLUSTER_NAMESPACE} --selector release=${RELEASE_NAME} -o json | jq -r '.items[].spec.ports[0] | [.name, .nodePort | tostring] | join(" -> http://"+"'"${IP_ADDR}"':") '
echo ""
# Select url of frontend service
export APP_URL=http://${IP_ADDR}:$( kubectl get services --namespace ${CLUSTER_NAMESPACE} --selector release=${RELEASE_NAME},group=frontend -o json | jq -r '.items[].spec.ports[0].nodePort ' )
echo -e "VIEW THE FRONT-END APPLICATION AT: ${APP_URL}"

