#!/bin/bash
# uncomment to debug the script
# set -x
# This script does build a Docker image using Docker-in-Docker into IBM Container Service private image registry,
# and copies information into a build.properties file, so they can be reused later on by other scripts
# (e.g. image url, chart name, ...)

if [ -z "$REGISTRY_URL" ]; then
  # Initialize REGISTRY_URL with the ibmcloud cr info output
  export REGISTRY_URL=$(ibmcloud cr info | grep -i '^Container Registry' | sort | head -1 | awk '{print $3;}')
fi

echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "GIT_COMMIT=${GIT_COMMIT}"
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

echo -e "Existing images in registry"
ibmcloud cr images

# Minting image tag using format: BUILD_NUMBER--BRANCH-COMMIT_ID-TIMESTAMP
# e.g. 3-master-50da6912-20181123114435
# (use build number as first segment to allow image tag as a patch release name according to semantic versioning)

TIMESTAMP=$( date -u "+%Y%m%d%H%M%S")
IMAGE_TAG=${TIMESTAMP}
if [ ! -z "${GIT_COMMIT}" ]; then
  GIT_COMMIT_SHORT=$( echo ${GIT_COMMIT} | head -c 8 ) 
  IMAGE_TAG=${GIT_COMMIT_SHORT}-${IMAGE_TAG}
fi
if [ ! -z "${GIT_BRANCH}" ]; then IMAGE_TAG=${GIT_BRANCH}-${IMAGE_TAG} ; fi
IMAGE_TAG=${BUILD_NUMBER}-${IMAGE_TAG}
echo "=========================================================="
echo -e "BUILDING CONTAINER IMAGE: ${IMAGE_NAME}:${IMAGE_TAG}"
if [ -z "${DOCKER_ROOT}" ]; then DOCKER_ROOT=. ; fi
if [ -z "${DOCKER_FILE}" ]; then DOCKER_FILE=Dockerfile ; fi

docker build --tag "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG" -f ${DOCKER_ROOT}/${DOCKER_FILE} ${DOCKER_ROOT}
RC=$?
if [ "$RC" != "0" ]; then
  exit $RC
fi

docker inspect ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}

# Set PIPELINE_IMAGE_URL for subsequent jobs in stage (e.g. Vulnerability Advisor)
export PIPELINE_IMAGE_URL="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"

export DCT_DISABLED=${DCT_DISABLED:-true}
docker push --disable-content-trust=$DCT_DISABLED "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG" 
RC=$?
if [ "$RC" != "0" ]; then
  exit $RC
fi

ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

######################################################################################
# Copy any artifacts that will be needed for deployment and testing to $WORKSPACE    #
######################################################################################
echo "=========================================================="
echo "COPYING ARTIFACTS needed for deployment and testing (in particular build.properties)"

echo "Checking archive dir presence"
if [ -z "${ARCHIVE_DIR}" ]; then
  echo -e "Build archive directory contains entire working directory."
else
  echo -e "Copying working dir into build archive directory: ${ARCHIVE_DIR} "
  mkdir -p ${ARCHIVE_DIR}
  find . -mindepth 1 -maxdepth 1 -not -path "./$ARCHIVE_DIR" -exec cp -R '{}' "${ARCHIVE_DIR}/" ';'
fi

# Persist env variables into a properties file (build.properties) so that all pipeline stages consuming this
# build as input and configured with an environment properties file valued 'build.properties'
# will be able to reuse the env variables in their job shell scripts.

# If already defined build.properties from prior build job, append to it.
cp build.properties $ARCHIVE_DIR/ || :

# IMAGE information from build.properties is used in Helm Chart deployment to set the release name
echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/build.properties
echo "IMAGE_TAG=${IMAGE_TAG}" >> $ARCHIVE_DIR/build.properties
# REGISTRY information from build.properties is used in Helm Chart deployment to generate cluster secret
echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_REGION=${REGISTRY_REGION}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/build.properties
echo "GIT_BRANCH=${GIT_BRANCH}" >> $ARCHIVE_DIR/build.properties
echo "File 'build.properties' created for passing env variables to subsequent pipeline jobs:"
cat $ARCHIVE_DIR/build.properties
