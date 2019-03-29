#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/publish_umbrella_helm_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/publish_umbrella_helm_chart.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_umbrella_helm_chart.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_umbrella_helm_chart.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "GIT_URL=${SOURCE_GIT_URL}"
echo "GIT_COMMIT=${SOURCE_GIT_COMMIT}"
echo "GIT_USER=${SOURCE_GIT_USER}"
echo "GIT_PASSWORD=${SOURCE_GIT_PASSWORD}"
echo "UMBRELLA_REPO_NAME=${UMBRELLA_REPO_NAME}"
echo "CHART_PATH=${CHART_PATH}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "SOURCE_BUILD_NUMBER=${SOURCE_BUILD_NUMBER}"
echo "PIPELINE_STAGE_INPUT_REV=${PIPELINE_STAGE_INPUT_REV}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
# Insights variables
echo "BUILD_PREFIX=${BUILD_PREFIX}"
echo "LOGICAL_APP_NAME=${LOGICAL_APP_NAME}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
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
echo -e "Located umbrella repo: ${UMBRELLA_REPO_URL}, with access token: ${UMBRELLA_ACCESS_REPO_URL}"
git config --global user.email "autobuild@not-an-email.com"
git config --global user.name "Automatic Build: ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}"
git config --global push.default simple

echo "=========================================================="
echo "PREPARING CHART PACKAGE"
echo -e "Checking existence of ${CHART_PATH}"
if [ ! -d ${CHART_PATH} ]; then
    echo -e "Helm chart: ${CHART_PATH} NOT found"
    exit 1
fi
# Compute chart version number
CHART_VERSION=$(cat ${CHART_PATH}/Chart.yaml | grep '^version:' | awk '{print $2}')
MAJOR=`echo ${CHART_VERSION} | cut -d. -f1`
MINOR=`echo ${CHART_VERSION} | cut -d. -f2`
REVISION=`echo ${CHART_VERSION} | cut -d. -f3`
if [ -z ${MAJOR} ]; then MAJOR=0; fi
if [ -z ${MINOR} ]; then MINOR=0; fi
if [ -z ${REVISION} ]; then REVISION=${BUILD_NUMBER}; else REVISION=${REVISION}-${BUILD_NUMBER}; fi
VERSION="${MAJOR}.${MINOR}.${REVISION}"
echo -e "VERSION:${VERSION}"
#echo -e "Injecting pipeline build values into ${CHART_PATH}/Chart.yaml"
#sed -i "s~^\([[:blank:]]*\)version:.*$~\version: ${VERSION}~" ${CHART_PATH}/Chart.yaml
echo -e "Injecting pipeline build values into ${CHART_PATH}/values.yaml"
sed -i "s~^\([[:blank:]]*\)repository:.*$~\1repository: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}~" ${CHART_PATH}/values.yaml
sed -i "s~^\([[:blank:]]*\)tag:.*$~\1tag: ${BUILD_NUMBER}~" ${CHART_PATH}/values.yaml
# TODO: revisit above after https://github.com/kubernetes/helm/issues/3141
echo "Linting injected Helm chart"
helm init --client-only
helm lint ${CHART_PATH}

# Evaluate the gate against the version (reprsented by $SOURCE_BUILD_NUMBER) matching the git commit
if [ "${SOURCE_BUILD_NUMBER}" ]; then 
  export PIPELINE_STAGE_INPUT_REV=${SOURCE_BUILD_NUMBER}
fi

echo "Capture Insights matching config"
mkdir -p ./.publish/insights
INSIGHTS_FILE=./.publish/insights/${CHART_NAME}-${VERSION}
rm -f INSIGHTS_FILE # override if already exists
echo "TOOLCHAIN_ID=${PIPELINE_TOOLCHAIN_ID}" >> $INSIGHTS_FILE
echo "BUILD_PREFIX=${BUILD_PREFIX}" >> $INSIGHTS_FILE
echo "LOGICAL_APP_NAME=${LOGICAL_APP_NAME}" >> $INSIGHTS_FILE
echo "PIPELINE_STAGE_INPUT_REV=${PIPELINE_STAGE_INPUT_REV}" >> $INSIGHTS_FILE
cat $INSIGHTS_FILE

# Add the insights file in the packaged umbrella helm chart
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
  echo "Inject component chart"
  mkdir -p ./${UMBRELLA_REPO_NAME}/charts
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