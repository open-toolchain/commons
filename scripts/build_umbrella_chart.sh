#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/build_umbrella_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/build_umbrella_chart.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_umbrella_chart.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_umbrella_chart.sh

# This script does build a complete umbrella chart with resolved dependencies, leveraging a sibling local chart repo (/charts)
# which would be updated from respective CI pipelines (see also https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_helm_package.sh)
CHART_NAME=${CHART_NAME:-'umbrella-chart'}
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "CHART_NAME=${CHART_NAME}"

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
VERSION_OF_HELM=$(helm version)
echo "${VERSION_OF_HELM}"
if [[ "$VERSION_OF_HELM" != *"v3."* ]]; then
  helm init --client-only
fi

#echo "Checking archive dir presence"
#cp -R -n ./ $ARCHIVE_DIR/ || true

#GIT_REMOTE_URL=$( git config --get remote.origin.url )
#echo -e "REPO:${GIT_REMOTE_URL%'.git'}/raw/master/charts"
#cat <(curl -sSL "${GIT_REMOTE_URL}/raw/master/charts/index.yaml")
#helm repo add components ${GIT_REMOTE_URL}/raw/master/charts
#helm repo add components "${GIT_REMOTE_URL%'.git'}/raw/master/charts"

CHART_PATH=./${CHART_NAME}

# Compute chart version number
TIMESTAMP=$( date -u "+%Y%m%d%H%M%SUTC")
REVISION_INFO=${BUILD_NUMBER}-${TIMESTAMP}
if [ ! -z ${GIT_COMMIT} ]; then
  GIT_COMMIT_SHORT=$( echo ${GIT_COMMIT} | head -c 8 ) 
  REVISION_INFO=${IMAGE_TAG}-${GIT_COMMIT_SHORT}; 
fi

CHART_VERSION=$(cat ${CHART_PATH}/Chart.yaml | grep '^version:' | awk '{print $2}')
CHART_VERSION="${CHART_VERSION%\"}"
CHART_VERSION="${CHART_VERSION#\"}"
MAJOR=`echo ${CHART_VERSION} | cut -d. -f1`
MINOR=`echo ${CHART_VERSION} | cut -d. -f2`
REVISION=`echo ${CHART_VERSION} | cut -d. -f3`
if [ -z ${MAJOR} ]; then MAJOR=0; fi
if [ -z ${MINOR} ]; then MINOR=0; fi
if [ -z ${REVISION} ]; then REVISION=${REVISION_INFO}; else REVISION=${REVISION}.${REVISION_INFO}; fi
VERSION="${MAJOR}.${MINOR}.${REVISION}"
echo -e "VERSION:${VERSION}"

# regenerate index to use local file path
#helm repo index ./charts --url "file://../charts"
#helm dependency update --debug ${CHART_PATH}

# TEMPORARY solution, until figured https://github.com/kubernetes/helm/issues/3585
# copy latest version of each component chart (assuming requirements.yaml was intending so)
mkdir -p ${CHART_PATH}/charts
echo "Component charts available:"
ls ./charts/*.tgz

if [[ "$VERSION_OF_HELM" == *"v3."* ]]; then
  # add quotes around the version entry in the chart for helm3 if not already present
  UPDATED_CHART_VERSION='"'"${CHART_VERSION}"'"'
  sed -i "s~^\([[:blank:]]*\)version:.*$~\1version: ${UPDATED_CHART_VERSION}~" ${CHART_PATH}/Chart.yaml
fi

for COMPONENT_NAME in $( grep "name:" ${CHART_NAME}/requirements.yaml | awk '{print $3}' ); do
  COMPONENT_CHART=$(find ./charts/${COMPONENT_NAME}* -maxdepth 1 | sort --version-sort --field-separator=- --key=2,2 | tail -n 1 )
  cp ${COMPONENT_CHART} ${CHART_PATH}/charts
done

# copy latest version of each component insights config
if [[ -d ./insights ]]; then
  mkdir -p ${CHART_PATH}/insights
  echo "Insights config files available:"
  ls ./insights/*
  for COMPONENT_NAME in $( grep "name:" ${CHART_NAME}/requirements.yaml | awk '{print $3}' ); do
    COMPONENT_CONFIG=$(find ./insights/${COMPONENT_NAME}* -maxdepth 1 | sort --version-sort --field-separator=- --key=2,2 | tail -n 1 )
    cp ${COMPONENT_CONFIG} ${CHART_PATH}/insights
  done
fi

echo "Umbrella chart with updated dependencies:"
ls -R ${CHART_PATH}
helm lint ${CHART_PATH}

echo "=========================================================="
echo "COPYING ARTIFACTS needed for deployment and testing (in particular build.properties)"

echo "Checking archive dir presence"
mkdir -p $ARCHIVE_DIR

# Persist env variables into a properties file (build.properties) so that all pipeline stages consuming this
# build as input and configured with an environment properties file valued 'build.properties'
# will be able to reuse the env variables in their job shell scripts.

# If already defined build.properties from prior build job, append to it.
cp build.properties $ARCHIVE_DIR || :

# CHART information from build.properties is used in Helm Chart deployment to set the release name
echo "CHART_PATH=${CHART_PATH}" >> $ARCHIVE_DIR/build.properties
echo "CHART_NAME=${CHART_NAME}" >> $ARCHIVE_DIR/build.properties
# IMAGE information from build.properties is used in Helm Chart deployment to set the release name
echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/build.properties
echo "PIPELINE_STAGE_INPUT_REV=${PIPELINE_STAGE_INPUT_REV}" >> $ARCHIVE_DIR/build.properties
# REGISTRY information from build.properties is used in Helm Chart deployment to generate cluster secret
echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/build.properties
echo "File 'build.properties' created for passing env variables to subsequent pipeline jobs:"
cat $ARCHIVE_DIR/build.properties | grep -v -i password

echo "Copy updated Helm umbrella chart"
cp -R -n ${CHART_PATH} ${ARCHIVE_DIR} || true

echo "Copy pipeline scripts along with the build"
cp -R -n ./scripts ${ARCHIVE_DIR}/scripts || true

echo "Copy umbrella insights, tests along with the build"
cp -R -n ./package.json ${ARCHIVE_DIR} || true
cp -R -n ./tests ${ARCHIVE_DIR}/tests || true
cp -R -n ./insights ${ARCHIVE_DIR}/insights || true