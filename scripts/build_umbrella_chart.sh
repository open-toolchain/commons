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

#echo "Checking archive dir presence"
#cp -R -n ./ $ARCHIVE_DIR/ || true

set -x
GIT_REMOTE_URL=$( git config --get remote.origin.url )

helm init --client-only
echo -e "REPO:${GIT_REMOTE_URL%'.git'}/raw/master/charts"
helm repo add components --no-update ${GIT_REMOTE_URL%".git"}/raw/master/charts
helm dependency build ./umbrella-chart
helm lint ./umbrella-chart

ls ./umbrella-chart/charts