#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/build_image_kubectl.sh) and 'source' it from your pipeline job
#    source ./scripts/build_image_kubectl.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image_kubectl.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_image_kubectl.sh

# This script does build a Docker image into IBM Container Service private image registry, updating kubectl deploy files, and 
# copies information into a build.properties file, so they can be reused later on by other scripts (e.g. image url, chart name, ...)
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

echo "=========================================================="
echo "Checking for Dockerfile at the repository root"
if [ -f Dockerfile ]; then 
echo "Dockerfile found"
else
    echo "Dockerfile not found"
    exit 1
fi
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

TIMESTAMP=$( date -u "+%Y%m%d%H%M%SUTC")
IMAGE_TAG=${BUILD_NUMBER}-${TIMESTAMP}
if [ ! -z ${GIT_COMMIT} ]; then
  GIT_COMMIT_SHORT=$( echo ${GIT_COMMIT} | head -c 8 ) 
  IMAGE_TAG=${IMAGE_TAG}.${GIT_COMMIT_SHORT}; 
fi
echo "=========================================================="
echo -e "Building container image: ${IMAGE_NAME}:${IMAGE_TAG}"
set -x
bx cr build -t ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG} .
set +x
bx cr image-inspect ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}

# Set PIPELINE_IMAGE_URL for subsequent jobs in stage (e.g. Vulnerability Advisor)
export PIPELINE_IMAGE_URL="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"

bx cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

######################################################################################
# Copy any artifacts that will be needed for deployment and testing to $WORKSPACE    #
######################################################################################
echo -e "Checking archive dir presence"
mkdir -p $ARCHIVE_DIR
# If already defined build.properties from prior build job, append to it.
cp build.properties $ARCHIVE_DIR/ || :
# pass image information along via build.properties for Vulnerability Advisor scan
echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/build.properties
echo "IMAGE_TAG=${IMAGE_TAG}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/build.properties
echo "File 'build.properties' created for passing env variables to subsequent pipeline jobs:"
cat $ARCHIVE_DIR/build.properties      
#Update deployment.yml with image name
if [ -f deployment.yml ]; then
    echo "UPDATING DEPLOYMENT MANIFEST:"
    sed -i "s~^\([[:blank:]]*\)image:.*$~\1image: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}~" deployment.yml
    cat deployment.yml
    if [ ! -f $ARCHIVE_DIR/deployment.yml ]; then # no need to copy if working in ./ already    
        cp deployment.yml $ARCHIVE_DIR/
    fi
else 
    echo -e "${red}Kubernetes deployment file 'deployment.yml' not found at the repository root${no_color}"
    exit 1
fi     