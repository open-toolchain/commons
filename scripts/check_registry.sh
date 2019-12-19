#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_registry.sh) and 'source' it from your pipeline job
#    source ./scripts/check_registry.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_registry.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_registry.sh

# This script checks presence of registry namespace.

# Input env variables (can be received via a pipeline environment properties.file.
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "DOCKER_ROOT=${DOCKER_ROOT}"
echo "DOCKER_FILE=${DOCKER_FILE}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties | grep -v -i password
else 
  echo "build.properties : not found"
fi 
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://cloud.ibm.com/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

echo "=========================================================="
echo "Checking registry current plan and quota"
ibmcloud cr plan || true
ibmcloud cr quota || true
echo "If needed, discard older images using: ibmcloud cr image-rm"
echo "Checking registry namespace: ${REGISTRY_NAMESPACE}"
NS=$( ibmcloud cr namespaces | grep ${REGISTRY_NAMESPACE} ||: )
if [ -z "${NS}" ]; then
    echo "Registry namespace ${REGISTRY_NAMESPACE} not found, creating it."
    ibmcloud cr namespace-add ${REGISTRY_NAMESPACE}
    echo "Registry namespace ${REGISTRY_NAMESPACE} created."
else 
    echo "Registry namespace ${REGISTRY_NAMESPACE} found."
fi
echo -e "Existing images in registry"
ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}

# echo "=========================================================="
# KEEP=1
# echo -e "PURGING REGISTRY, only keeping last ${KEEP} image(s) based on image digests"
# COUNT=0
# LIST=$( ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME} --no-trunc --format '{{ .Created }} {{ .Repository }}@{{ .Digest }}' | sort -r -u | awk '{print $2}' | sed '$ d' )
# while read -r IMAGE_URL ; do
#   if [[ "$COUNT" -lt "$KEEP" ]]; then
#     echo "Keeping image digest: ${IMAGE_URL}"
#   else
#     ibmcloud cr image-rm "${IMAGE_URL}"
#   fi
#   COUNT=$((COUNT+1)) 
# done <<< "$LIST"
# if [[ "$COUNT" -gt 1 ]]; then
#   echo "Content of image registry"
#   ibmcloud cr images
# fi
