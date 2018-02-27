#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/publish_helm_package.sh) and 'source' it from your pipeline job
#    source ./scripts/publish_helm_package.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_helm_package.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_helm_package.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "SOURCE_GIT_URL=${SOURCE_GIT_URL}"
echo "SOURCE_GIT_COMMIT=${SOURCE_GIT_COMMIT}"
echo "SOURCE_GIT_USER=${SOURCE_GIT_USER}"
echo "SOURCE_GIT_PASSWORD=${SOURCE_GIT_PASSWORD}"
echo "UMBRELLA_REPO_NAME=${UMBRELLA_REPO_NAME}"
echo "CHART_NAME=${CHART_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"

#View build properties
# cat build.properties
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

echo "=========================================================="
echo "FETCHING UMBRELLA repo"
echo -e "Locating target umbrella repo: ${UMBRELLA_REPO_NAME}"
TOOLCHAIN_SERVICES=$( curl -H "Authorization: ${TOOLCHAIN_TOKEN}" https://otc-api.ng.bluemix.net/api/v1/toolchains/${PIPELINE_TOOLCHAIN_ID}/services )
UMBRELLA_REPO_URL=$( echo ${TOOLCHAIN_SERVICES} | jq -r '.services[] | select (.parameters.repo_name=="'"${UMBRELLA_REPO_NAME}"'") | .parameters.repo_url ' )
# Augment URL with git user & password
UMBRELLA_REPO_URL=${UMBRELLA_REPO_URL:0:8}${SOURCE_GIT_USER}:${SOURCE_GIT_PASSWORD}@${UMBRELLA_REPO_URL:8}
UMBRELLA_REPO_URL=${UMBRELLA_REPO_URL%".git"} #remove trailing .git if present
echo -e "Located umbrella repo: ${UMBRELLA_REPO_URL}"

echo -e "Fetching umbrella repo (to then commit a new packaged version of the chart for component: ${CHART_NAME}"
git config --global user.email "autobuild@not-an-email.com"
git config --global user.name "Automatic Build: ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}"
git config --global push.default simple
git clone ${UMBRELLA_REPO_URL}

ls -al

echo "=========================================================="
echo "PREPARING CHART PACKAGE"
echo -e "Checking existence of /chart/${CHART_NAME}"
if [ ! -d ./chart/${CHART_NAME} ]; then
    echo -e "Helm chart: ./chart/${CHART_NAME} NOT found"
    exit 1
fi
# Compute chart version number
CHART_VERSION=$(cat ./chart/${CHART_NAME}/Chart.yaml | grep '^version:' | awk '{print $2}')
MAJOR=`echo ${CHART_VERSION} | cut -d. -f1`
MINOR=`echo ${CHART_VERSION} | cut -d. -f2`
REVISION=`echo ${CHART_VERSION} | cut -d. -f3`
if [ -z ${MAJOR} ]; then MAJOR=0; fi
if [ -z ${MINOR} ]; then MINOR=0; fi
if [ -z ${REVISION} ]; then REVISION=${BUILD_NUMBER}; else REVISION=${REVISION}-b${BUILD_NUMBER}; fi
VERSION="${MAJOR}.${MINOR}.${REVISION}"
echo -e "VERSION:${VERSION}"
#echo -e "Injecting pipeline build values into /chart/${CHART_NAME}/Chart.yaml"
#sed -i "s~^\([[:blank:]]*\)version:.*$~\version: ${VERSION}~" ./chart/${CHART_NAME}/Chart.yaml
echo -e "Injecting pipeline build values into /chart/${CHART_NAME}/values.yaml"
sed -i "s~^\([[:blank:]]*\)repository:.*$~\1repository: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}~" ./chart/${CHART_NAME}/values.yaml
sed -i "s~^\([[:blank:]]*\)tag:.*$~\1tag: ${BUILD_NUMBER}~" ./chart/${CHART_NAME}/values.yaml
# TODO: revisit above after https://github.com/kubernetes/helm/issues/3141
echo "Linting injected Helm chart"
helm init --client-only
helm lint ./chart/${CHART_NAME}
echo "Packaging chart"
mkdir -p ./${UMBRELLA_REPO_NAME}/charts
helm package ./chart/${CHART_NAME} --version $VERSION -d ./${UMBRELLA_REPO_NAME}/charts

echo "=========================================================="
echo "PUBLISH CHART PACKAGE"
# Refresh in case of concurrent updates
git -C ./${UMBRELLA_REPO_NAME} pull --no-edit
echo "Updating charts index"
# touch ./${UMBRELLA_REPO_NAME}/charts/index.yaml
helm repo index ./${UMBRELLA_REPO_NAME}/charts ./${UMBRELLA_REPO_NAME}/charts/index.yaml --url ${UMBRELLA_REPO_URL}/tree/master/charts

cd ${UMBRELLA_REPO_NAME}
git add .
git status
git commit -m "Published chart: ${CHART_NAME}:${VERSION} from ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}. Source: ${SOURCE_GIT_URL} commit: ${SOURCE_GIT_COMMIT}"
git push -f