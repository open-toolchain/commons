#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_prebuild.sh) and 'source' it from your pipeline job
#    source ./scripts/check_prebuild.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_prebuild.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_prebuild.sh
echo "Build environment variables:"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

echo "=========================================================="
echo "CHECKING DOCKERFILE"
echo "Checking Dockerfile at the repository root"
if [ -f Dockerfile ]; then 
   echo "Dockerfile found"
else
    echo "Dockerfile not found"
    exit 1
fi
echo "Linting Dockerfile"
npm install -g dockerlint
dockerlint -f Dockerfile

echo "=========================================================="
echo "CHECKING HELM CHART"
echo "Looking for chart under /chart/<CHART_NAME>"
CHART_ROOT="chart"

if [ -d ${CHART_ROOT} ]; then
  CHART_NAME=$(find ${CHART_ROOT}/. -maxdepth 2 -type d -name '[^.]?*' -printf %f -quit)
  CHART_PATH=${CHART_ROOT}/${CHART_NAME}
fi
if [ -z "${CHART_PATH}" ]; then
    echo -e "No Helm chart found for Kubernetes deployment under ${CHART_ROOT}/<CHART_NAME>."
    exit 1
else
    echo -e "Helm chart found for Kubernetes deployment : ${CHART_PATH}"
fi
echo "Linting Helm Chart"
helm lint ${CHART_PATH}

echo "=========================================================="
echo "CHECKING REGISTRY namespace, current plan and quota"
bx cr plan
bx cr quota
echo "Checking registry namespace: ${REGISTRY_NAMESPACE}"
NS=$( bx cr namespaces | grep ${REGISTRY_NAMESPACE} ||: )
if [ -z "${NS}" ]; then
    echo -e "Registry namespace ${REGISTRY_NAMESPACE} not found, creating it."
    bx cr namespace-add ${REGISTRY_NAMESPACE}
    echo -e "Registry namespace ${REGISTRY_NAMESPACE} created."
else 
    echo -e "Registry namespace ${REGISTRY_NAMESPACE} found."
fi
echo -e "Current content of image registry namespace: ${REGISTRY_NAMESPACE}"
bx cr images --restrict ${REGISTRY_NAMESPACE}

# echo "=========================================================="
# KEEP=1
# echo -e "PURGING REGISTRY, only keeping last ${KEEP} image(s) based on image digests"
# COUNT=0
# LIST=$( bx cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME} --no-trunc --format '{{ .Created }} {{ .Repository }}@{{ .Digest }}' | sort -r -u | awk '{print $2}' | sed '$ d' )
# while read -r IMAGE_URL ; do
#   if [[ "$COUNT" -lt "$KEEP" ]]; then
#     echo "Keeping image digest: ${IMAGE_URL}"
#   else
#     bx cr image-rm "${IMAGE_URL}"
#   fi
#   COUNT=$((COUNT+1)) 
# done <<< "$LIST"
# if [[ "$COUNT" -gt 1 ]]; then
#   echo "Content of image registry"
#   bx cr images
# fi
