#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/deploy_umbrella_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/deploy_helm.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_umbrella_chart.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_umbrella_chart.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "CHART_PATH=${CHART_PATH}"
echo "IMAGE_NAME=${IMAGE_NAME}" # TODO improve into RELEASE NAME
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "PIPELINE_STAGE_INPUT_REV=${PIPELINE_STAGE_INPUT_REV}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "LOGICAL_ENV_NAME=${LOGICAL_ENV_NAME}"

#View build properties
# cat build.properties
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

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
echo "DEPLOYING HELM chart"
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

# Using 'upgrade --install" for rolling updates. Note that subsequent updates will occur in the same namespace the release is currently deployed in, ignoring the explicit--namespace argument".
echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade --install --debug --dry-run ${RELEASE_NAME} ${CHART_PATH} --set global.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

echo -e "Deploying into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${CLUSTER_NAMESPACE}."
helm upgrade  --install ${RELEASE_NAME} ${CHART_PATH} --set global.pullSecret=${IMAGE_PULL_SECRET_NAME} --namespace ${CLUSTER_NAMESPACE}

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
if [[ ! -d ./insights ]]; then
  echo "Cannot find Insights config information in /insights folder"
else
  # Install DRA CLI
  export PATH=/opt/IBM/node-v4.2/bin:$PATH
  npm install -g grunt-idra3

  # get the deployment result from helm status command
  STATUS=$( helm status ${RELEASE_NAME} | grep STATUS: | awk '{print $2}' )
  if [[ $STATUS -eq 'DEPLOYED' ]]; then
      STATUS='pass'
  else
      STATUS='fail'
  fi

  ls ./insights/*
  echo "LOGICAL_ENV_NAME=${LOGICAL_ENV_NAME}"
  for INSIGHT_CONFIG in $( ls -v ${CHART_PATH}/insights); do
    echo -e "Publish results for component: ${INSIGHT_CONFIG}"
    export LOGICAL_APP_NAME=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep LOGICAL_APP_NAME | cut -d'=' -f2 )
    export BUILD_PREFIX=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep BUILD_PREFIX | cut -d'=' -f2 )
    export PIPELINE_STAGE_INPUT_REV=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep PIPELINE_STAGE_INPUT_REV | cut -d'=' -f2 )
    echo -e "LOGICAL_APP_NAME: ${LOGICAL_APP_NAME}"
    echo -e "BUILD_PREFIX: ${BUILD_PREFIX}"
    echo -e "PIPELINE_STAGE_INPUT_REV: ${PIPELINE_STAGE_INPUT_REV}"

    # publish deploy records for 3 microservices
    idra --publishdeployrecord  --env=${LOGICAL_ENV_NAME} --status=${STATUS}

    # get the process exit code
    RESULT=$?  
    if [[ ${RESULT} != 0 ]]; then
        exit ${RESULT}
    fi
  done
fi

echo "=========================================================="
IP_ADDR=$(bx cs workers ${PIPELINE_KUBERNETES_CLUSTER_NAME} | grep normal | head -n 1 | awk '{ print $2 }')

echo -e "Deployed services:"
kubectl get services --namespace ${CLUSTER_NAMESPACE} --selector release=${RELEASE_NAME} -o json | jq -r '.items[].spec.ports[0] | [.name, .nodePort | tostring] | join(" -> http://"+"'"${IP_ADDR}"':") '
echo ""
# Select url of frontend service
export APP_URL=http://${IP_ADDR}:$( kubectl get services --namespace ${CLUSTER_NAMESPACE} --selector release=${RELEASE_NAME},group=frontend -o json | jq -r '.items[].spec.ports[0].nodePort ' )
echo -e "VIEW THE FRONT-END APPLICATION AT: ${APP_URL}"

