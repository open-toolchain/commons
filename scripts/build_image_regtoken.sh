#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/build_image_regtoken.sh) and 'source' it from your pipeline job
#    source ./scripts/build_image_regtoken.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image_regtoken.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image_regtoken.sh

# This script does build a Docker image into IBM Container Service private image registry, and copies information into
# a build.properties file, so they can be reused later on by other scripts (e.g. image url, chart name, ...)
# Also provisions a private image registry token (to be used for image pull secret in Kubernetes cluster)
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"

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

# To review or change build options use:
# ibmcloud cr build --help

echo -e "Existing images in registry"
ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}

TIMESTAMP=$( date -u "+%Y%m%d%H%M%SUTC")
IMAGE_TAG=${BUILD_NUMBER}-${TIMESTAMP}
if [ ! -z ${GIT_COMMIT} ]; then
  GIT_COMMIT_SHORT=$( echo ${GIT_COMMIT} | head -c 8 ) 
  IMAGE_TAG=${IMAGE_TAG}-${GIT_COMMIT_SHORT}; 
fi
echo "=========================================================="
echo -e "Building container image: ${IMAGE_NAME}:${IMAGE_TAG}"
set -x
ibmcloud cr build -t ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG} .
set +x
ibmcloud cr image-inspect ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}

# Set PIPELINE_IMAGE_URL for subsequent jobs in stage (e.g. Vulnerability Advisor)
export PIPELINE_IMAGE_URL="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"

ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

# Provision a registry token for this toolchain to later pull image. Token will be passed into build.properties
echo "=========================================================="
TOKEN_DESCR="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}"
echo "CHECKING REGISTRY token existence for toolchain: ${TOKEN_DESCR}"
EXISTING_TOKEN=$(ibmcloud cr tokens | grep ${TOKEN_DESCR} ||: )
if [ -z "${EXISTING_TOKEN}" ]; then
    echo -e "Creating new registry token: ${TOKEN_DESCR}"
    ibmcloud cr token-add --non-expiring --description ${TOKEN_DESCR}
    REGISTRY_TOKEN_ID=$(ibmcloud cr tokens | grep ${TOKEN_DESCR} | awk '{ print $1 }')
else    
    echo -e "Reusing existing registry token: ${TOKEN_DESCR}"
    REGISTRY_TOKEN_ID=$(echo $EXISTING_TOKEN | awk '{ print $1 }')
fi
REGISTRY_TOKEN=$(ibmcloud cr token-get ${REGISTRY_TOKEN_ID} --quiet)
echo -e "REGISTRY_TOKEN=${REGISTRY_TOKEN}"

echo "=========================================================="
echo "COPYING ARTIFACTS needed for deployment and testing (in particular build.properties)"

echo "Checking archive dir presence"
mkdir -p $ARCHIVE_DIR
# If already defined build.properties from prior build job, append to it.
cp build.properties $ARCHIVE_DIR/ || :

# Persist env variables into a properties file (build.properties) so that all pipeline stages consuming this
# build as input and configured with an environment properties file valued 'build.properties'
# will be able to reuse the env variables in their job shell scripts.

# CHART information from build.properties is used in Helm Chart deployment to set the release name
CHART_NAME=$(find chart/. -maxdepth 2 -type d -name '[^.]?*' -printf %f -quit)
echo "CHART_NAME=${CHART_NAME}" >> $ARCHIVE_DIR/build.properties
# IMAGE information from build.properties is used in Helm Chart deployment to set the release name
echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/build.properties
echo "IMAGE_TAG=${IMAGE_TAG}" >> $ARCHIVE_DIR/build.properties
# REGISTRY information from build.properties is used in Helm Chart deployment to generate cluster secret
echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_TOKEN=${REGISTRY_TOKEN}" >> $ARCHIVE_DIR/build.properties
echo "File 'build.properties' created for passing env variables to subsequent pipeline jobs:"
cat $ARCHIVE_DIR/build.properties | grep -v -i password

echo "Copy pipeline scripts along with the build"
# Copy scripts (incl. deploy scripts)
if [ -d ./scripts/ ]; then
  if [ ! -d $ARCHIVE_DIR/scripts/ ]; then # no need to copy if working in ./ already
    cp -r ./scripts/ $ARCHIVE_DIR/
  fi
fi

echo "Copy Helm chart along with the build"
if [ ! -d $ARCHIVE_DIR/chart/ ]; then # no need to copy if working in ./ already
  cp -r ./chart/ $ARCHIVE_DIR/
fi