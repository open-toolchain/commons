#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_prebuild.sh) and 'source' it from your pipeline job
#    source ./scripts/check_prebuild.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_prebuild.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_prebuild.sh
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "DOCKER_ROOT=${DOCKER_ROOT}"
echo "DOCKER_FILE=${DOCKER_FILE}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
else 
  echo "build.properties : not found"
fi 
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

echo "=========================================================="
echo "Checking for Dockerfile at the repository root"
if [ -z "${DOCKER_ROOT}" ]; then DOCKER_ROOT=. ; fi
if [ -z "${DOCKER_FILE}" ]; then DOCKER_FILE=Dockerfile ; fi
if [ -f ${DOCKER_ROOT}/${DOCKER_FILE} ]; then 
echo -e "Dockerfile found at: ${DOCKER_FILE}"
else
    echo "Dockerfile not found at: ${DOCKER_FILE}"
    exit 1
fi
echo "Linting Dockerfile"
npm install -g dockerlint
dockerlint -f Dockerfile

echo "=========================================================="
echo "Checking registry current plan and quota"
bx cr plan
bx cr quota
echo "If needed, discard older images using: bx cr image-rm"
echo "Checking registry namespace: ${REGISTRY_NAMESPACE}"
NS=$( bx cr namespaces | grep ${REGISTRY_NAMESPACE} ||: )
if [ -z "${NS}" ]; then
    echo "Registry namespace ${REGISTRY_NAMESPACE} not found, creating it."
    bx cr namespace-add ${REGISTRY_NAMESPACE}
    echo "Registry namespace ${REGISTRY_NAMESPACE} created."
else 
    echo "Registry namespace ${REGISTRY_NAMESPACE} found."
fi
echo -e "Existing images in registry"
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
