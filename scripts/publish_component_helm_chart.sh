#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/publish_component_helm_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/publish_component_helm_chart.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_component_helm_chart.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_component_helm_chart.sh

# Publish a component chart into an umbrella chart stored in a git repo

# Input env variables (can be received via a pipeline environment properties.file.
echo "SOURCE_GIT_URL=${SOURCE_GIT_URL}"
echo "SOURCE_GIT_COMMIT=${SOURCE_GIT_COMMIT}"
echo "SOURCE_GIT_USER=${SOURCE_GIT_USER}"
if [ -z "${SOURCE_GIT_PASSWORD}" ]; then
  echo "SOURCE_GIT_PASSWORD="
else
  echo "SOURCE_GIT_PASSWORD=***"
fi
echo "UMBRELLA_REPO_NAME=${UMBRELLA_REPO_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "CHART_ROOT=${CHART_ROOT}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "SOURCE_BUILD_NUMBER=${SOURCE_BUILD_NUMBER}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
# Insights variables
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "APP_NAME=${APP_NAME}"

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
echo "CONFIGURING UMBRELLA CHART REPO"
echo -e "Locating target umbrella repo: ${UMBRELLA_REPO_NAME}"
ls -al
UMBRELLA_REPO_URL=$( cat _toolchain.json | jq -r '.services[] | select (.parameters.repo_name=="'"${UMBRELLA_REPO_NAME}"'") | .parameters.repo_url ' )
UMBRELLA_REPO_URL=${UMBRELLA_REPO_URL%".git"} #remove trailing .git if present
# Augment URL with git user & password
UMBRELLA_ACCESS_REPO_URL=${UMBRELLA_REPO_URL:0:8}${GIT_USER}:${GIT_PASSWORD}@${UMBRELLA_REPO_URL:8}
echo -e "Located umbrella repo: ${UMBRELLA_REPO_URL}, with access token: ${UMBRELLA_REPO_URL:0:8}${GIT_USER}:***@${UMBRELLA_REPO_URL:8}"
git config --global user.email "autobuild@not-an-email.com"
git config --global user.name "Automatic Build: ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}"
git config --global push.default simple

echo "=========================================================="
echo "PREPARING CHART PACKAGE"

echo "=========================================================="
echo "CHECKING HELM CHART"
if [ -z "${CHART_ROOT}" ]; then CHART_ROOT="chart" ; fi
echo -e "Looking for chart under /${CHART_ROOT}/<CHART_NAME>"
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

# Compute chart version number
CHART_VERSION=$(cat ${CHART_PATH}/Chart.yaml | grep '^version:' | awk '{print $2}')
MAJOR=`echo ${CHART_VERSION} | cut -d. -f1`
MINOR=`echo ${CHART_VERSION} | cut -d. -f2`
REVISION=`echo ${CHART_VERSION} | cut -d. -f3`
if [ -z ${MAJOR} ]; then MAJOR=0; fi
if [ -z ${MINOR} ]; then MINOR=0; fi
if [ -z ${REVISION} ]; then REVISION=${IMAGE_TAG}; else REVISION=${REVISION}-${IMAGE_TAG}; fi
VERSION="${MAJOR}.${MINOR}.${REVISION}"
echo -e "VERSION:${VERSION}"
#echo -e "Injecting pipeline build values into ${CHART_PATH}/Chart.yaml"
#sed -i "s~^\([[:blank:]]*\)version:.*$~\version: ${VERSION}~" ${CHART_PATH}/Chart.yaml
echo -e "Injecting pipeline build values into ${CHART_PATH}/values.yaml"
sed -i "s~^\([[:blank:]]*\)repository:.*$~\1repository: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}~" ${CHART_PATH}/values.yaml
sed -i "s~^\([[:blank:]]*\)tag:.*$~\1tag: ${IMAGE_TAG}~" ${CHART_PATH}/values.yaml
# TODO: revisit above after https://github.com/kubernetes/helm/issues/3141
echo "Linting injected Helm chart"
helm init --client-only
helm lint ${CHART_PATH}

echo "Note: this script has been updated to use ibmcloud doi plugin - iDRA being deprecated"
echo "iDRA based version of this script is located at: https://github.com/open-toolchain/commons/blob/v1.0.idra_based/scripts/publish_component_helm_chart.sh"

echo "Capture Insights matching config"
mkdir -p ./.publish/insights
INSIGHTS_FILE=./.publish/insights/${CHART_NAME}-${VERSION}
rm -f $INSIGHTS_FILE # override if already exists
# Evaluate the gate against the version matching the git commit
echo "TOOLCHAIN_ID=${PIPELINE_TOOLCHAIN_ID}" >> $INSIGHTS_FILE
echo "GIT_BRANCH=${GIT_BRANCH}" >> $INSIGHTS_FILE
echo "APP_NAME=${APP_NAME}" >> $INSIGHTS_FILE
echo "SOURCE_BUILD_NUMBER=${SOURCE_BUILD_NUMBER}" >> $INSIGHTS_FILE
cat $INSIGHTS_FILE

# Add the insights file in the packaged helm chart
cp $INSIGHTS_FILE ${CHART_PATH}/devops-insights.properties

echo "Packaging chart"
mkdir -p ./.publish/charts
helm package ${CHART_PATH} --version $VERSION -d ./.publish/charts

echo "=========================================================="
echo "PUBLISH CHART PACKAGE"
for ITER in {1..30}
do
  echo "Fetching umbrella repo"
  git clone ${UMBRELLA_ACCESS_REPO_URL}
  cd ${UMBRELLA_REPO_NAME}
  ls -al
  echo "Remove previous component data"
  ls -al
  rm -rf charts/${CHART_NAME}-*
  ls -al
  rm -rf insights/${CHART_NAME}-*
  echo "Inject component chart"
  mkdir -p charts
  cp -r ../.publish/. .
  echo "Updating charts index"
  helm repo index ./charts --url "${UMBRELLA_REPO_URL}/raw/master/charts"
  echo "Pushing commit"
  git add .
  git status
  git commit -m "Published chart: ${CHART_PATH}:${VERSION} from ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}. Source: ${GIT_URL%".git"}/commit/${GIT_COMMIT}"
  if git push ; then
    COMMIT_STATUS=OK
    break
  fi
  echo -e "Attempt ${ITER} : Commit failed. Likely due to concurrent commit from another component. Retrying shortly..."
  cd ..
  rm -rf ${UMBRELLA_REPO_NAME} ||:
  sleep 5
done
[[ $COMMIT_STATUS == "OK" ]] || { echo "ERROR: Unable to commit the packaged Helm chart, please check the log and try again."; exit 1; }

echo "SUCCESS: Committed packaged component to umbrella repo"
echo "Published chart: ${CHART_PATH}:${VERSION} from ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}. Source: ${GIT_URL%".git"}/commit/${GIT_COMMIT}"
echo "Umbrella repo commit:"
git ls-remote