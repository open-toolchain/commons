#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/build_image.sh) and 'source' it from your pipeline job
#    source ./scripts/build_image.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image.sh

# This script does build a Docker image into IBM Container Service private image registry, and copies information into
# a build.properties file, so they can be reused later on by other scripts (e.g. image url, chart name, ...)
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "GIT_COMMIT=${GIT_COMMIT}"

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

# To review or change build options use:
# bx cr build --help

echo -e "Existing images in registry"
bx cr images

TIMESTAMP=$( date -u "+%Y%m%d%H%M%SUTC")
IMAGE_TAG=${BUILD_NUMBER}-${TIMESTAMP}
if [ ! -z ${GIT_COMMIT} ]; then
  GIT_COMMIT_SHORT=$( echo ${GIT_COMMIT} | head -c 8 ) 
  IMAGE_TAG=${IMAGE_TAG}-${GIT_COMMIT_SHORT}; 
fi
echo "=========================================================="
echo -e "BUILDING CONTAINER IMAGE: ${IMAGE_NAME}:${IMAGE_TAG}"
set -x
bx cr build -t ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG} .
set +x
bx cr image-inspect ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}

# Set PIPELINE_IMAGE_URL for subsequent jobs in stage (e.g. Vulnerability Advisor)
export PIPELINE_IMAGE_URL="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"

bx cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

echo "=========================================================="
echo "COPYING ARTIFACTS needed for deployment and testing (in particular build.properties)"

echo "Checking archive dir presence"
mkdir -p $ARCHIVE_DIR

# Persist env variables into a properties file (build.properties) so that all pipeline stages consuming this
# build as input and configured with an environment properties file valued 'build.properties'
# will be able to reuse the env variables in their job shell scripts.

# If already defined build.properties from prior build job, append to it.
cp build.properties $ARCHIVE_DIR/ || :

CHART_ROOT="chart"
echo "Copy Helm chart along with the build"
if [ ! -d $ARCHIVE_DIR/CHART_ROOT ]; then # no need to copy if working in ./ already
  cp -r $CHART_ROOT $ARCHIVE_DIR/
fi

# CHART information from build.properties is used in Helm Chart deployment to set the release name
CHART_NAME=$(find ${CHART_ROOT}/. -maxdepth 2 -type d -name '[^.]?*' -printf %f -quit)
echo "CHART_NAME=${CHART_NAME}" >> $ARCHIVE_DIR/build.properties
echo "CHART_PATH=${CHART_ROOT}/${CHART_NAME}" >> $ARCHIVE_DIR/build.properties
# IMAGE information from build.properties is used in Helm Chart deployment to set the release name
echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/build.properties
echo "IMAGE_TAG=${IMAGE_TAG}" >> $ARCHIVE_DIR/build.properties
# REGISTRY information from build.properties is used in Helm Chart deployment to generate cluster secret
echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/build.properties
echo "File 'build.properties' created for passing env variables to subsequent pipeline jobs:"
cat $ARCHIVE_DIR/build.properties

echo "Copy pipeline scripts along with the build"
# Copy scripts (incl. deploy scripts)
if [ -d ./scripts/ ]; then
  if [ ! -d $ARCHIVE_DIR/scripts/ ]; then # no need to copy if working in ./ already
    cp -r ./scripts/ $ARCHIVE_DIR/
  fi
fi
