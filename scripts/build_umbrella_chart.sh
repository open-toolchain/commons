#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/build_umbrella_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/build_umbrella_chart.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_umbrella_chart.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/build_umbrella_chart.sh

# This script does build a complete umbrella chart with resolved dependencies, leveraging a sibling local chart repo (/charts)
# which would be updated from respective CI pipelines (see also https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_helm_package.sh)

echo "Build environment variables:"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"

#env
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

helm init --client-only

#echo "Checking archive dir presence"
#cp -R -n ./ $ARCHIVE_DIR/ || true

#GIT_REMOTE_URL=$( git config --get remote.origin.url )
#echo -e "REPO:${GIT_REMOTE_URL%'.git'}/raw/master/charts"
#cat <(curl -sSL "${GIT_REMOTE_URL}/raw/master/charts/index.yaml")
#helm repo add components ${GIT_REMOTE_URL}/raw/master/charts
#helm repo add components "${GIT_REMOTE_URL%'.git'}/raw/master/charts"

# regenerate index to use local file path
#helm repo index ./charts --url "file://../charts"
#helm dependency update --debug ./umbrella-chart

# TEMPORARY solution, until figured https://github.com/kubernetes/helm/issues/3585
# copy latest version of each component chart (assuming requirements.yaml was intending so)
mkdir -p ./umbrella-chart/charts
echo "Component charts available:"
ls ./charts/*.tgz
for COMPONENT_NAME in $( grep "name:" umbrella-chart/requirements.yaml | awk '{print $3}' ); do
  COMPONENT_CHART=$(find ./charts/${COMPONENT_NAME}* -maxdepth 1 | sort -r | head -n 1 )
  cp ${COMPONENT_CHART} ./umbrella-chart/charts
done
echo "Umbrella chart with updated dependencies:"
ls -R umbrella-chart

helm lint umbrella-chart

# copy updated umbrella chart
cp -R -n ./umbrella-chart ${ARCHIVE_DIR}/ || true

