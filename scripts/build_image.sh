#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/build_image.sh) and 'source' it from your pipeline job
#    source ./scripts/build_image.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image.sh")`
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image.sh
echo "Build environment variables:"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

# To review or change build options use:
# bx cr build --help

echo -e "Existing images in registry"
bx cr images

echo "=========================================================="
echo -e "BUILDING CONTAINER IMAGE: ${IMAGE_NAME}:${BUILD_NUMBER}"
set -x
bx cr build -t ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${BUILD_NUMBER} .
set +x
bx cr image-inspect ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${BUILD_NUMBER}

# When 'bx' commands are in the pipeline job config directly, the image URL will automatically be passed 
# along with the build result as env variable PIPELINE_IMAGE_URL to any subsequent job consuming this build result. 
# When the job is sourc'ing an external shell script, or to pass a different image URL than the one inferred by the pipeline,
# please uncomment and modify the environment variable the following line.
export PIPELINE_IMAGE_URL="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$BUILD_NUMBER"
echo "TODO - remove once no longer needed to unlock VA job ^^^^"

bx cr images

# Provision a registry token for this toolchain to later pull image. Token will be passed into build.properties
echo "=========================================================="
TOKEN_DESCR="bluemix-toolchain-${PIPELINE_TOOLCHAIN_ID}"
echo "CHECKING REGISTRY token existence for toolchain: ${TOKEN_DESCR}"
EXISTING_TOKEN=$(bx cr tokens | grep ${TOKEN_DESCR} ||: )
if [ -z ${EXISTING_TOKEN} ]; then
    echo -e "Creating new registry token: ${TOKEN_DESCR}"
    bx cr token-add --non-expiring --description ${TOKEN_DESCR}
    REGISTRY_TOKEN_ID=$(bx cr tokens | grep ${TOKEN_DESCR} | awk '{ print $1 }')
else    
    echo -e "Reusing existing registry token: ${TOKEN_DESCR}"
    REGISTRY_TOKEN_ID=$(echo $EXISTING_TOKEN | awk '{ print $1 }')
fi
REGISTRY_TOKEN=$(bx cr token-get ${REGISTRY_TOKEN_ID} --quiet)
echo -e "REGISTRY_TOKEN=${REGISTRY_TOKEN}"

echo "=========================================================="
echo "COPYING ARTIFACTS needed for deployment and testing (in particular build.properties)"

echo "Checking archive dir presence"
mkdir -p $ARCHIVE_DIR

# Persist env variables into a properties file (build.properties) so that all pipeline stages consuming this
# build as input and configured with an environment properties file valued 'build.properties'
# will be able to reuse the env variables in their job shell scripts.

# CHART information from build.properties is used in Helm Chart deployment to set the release name
CHART_NAME=$(find chart/. -maxdepth 2 -type d -name '[^.]?*' -printf %f -quit)
echo "CHART_NAME=${CHART_NAME}" >> $ARCHIVE_DIR/build.properties
# IMAGE information from build.properties is used in Helm Chart deployment to set the release name
echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/build.properties
echo "BUILD_NUMBER=${BUILD_NUMBER}" >> $ARCHIVE_DIR/build.properties
# REGISTRY information from build.properties is used in Helm Chart deployment to generate cluster secret
echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_TOKEN=${REGISTRY_TOKEN}" >> $ARCHIVE_DIR/build.properties
echo "File 'build.properties' created for passing env variables to subsequent pipeline jobs:"
cat $ARCHIVE_DIR/build.properties

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