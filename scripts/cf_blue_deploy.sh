#!/bin/bash
# uncomment to debug the script
#set -x
#CF_TRACE=true
# copy the script below into your app code repo (e.g. ./scripts/cf_bluedeploy.sh) and 'source' it from your pipeline job
#    source ./scripts/cf_bluedeploy.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_bluedeploy.sh")`
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_bluedeploy.sh

# BLUE/GREEN DEPLOY STEP 1/3
# Deploys a Cloud Foundry app on a test route, and exports the test app url
# This script should be run in a CF deploy job, in a stage declaring an env property: TEMP_APP_URL

echo "Build environment variables:"
echo "CF_APP_NAME=${CF_APP_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

# Compute a unique app name using the reserved CF_APP name (configured in the 
# deployer or from the manifest.yml file), the build number, and a 
# timestamp (allowing multiple deploys for the same build).
export TEMP_APP_NAME="${CF_APP_NAME}-${BUILD_NUMBER}-$(date +%s)"

echo "=========================================================="
echo -e "DEPLOYING test blue app: ${TEMP_APP_NAME}"
# push the application, do not start it until all env properties are set
cf push $TEMP_APP_NAME --no-start
# cf set-env $TEMP_APP_NAME <property> <value>
cf start $TEMP_APP_NAME -t 180 # grants 180s for app to fully start
# retrieve the temp app domain and url
cf apps | grep $TEMP_APP_NAME
url=$(cf app $TEMP_APP_NAME | grep urls: | awk '{print $2}')
prefix="${TEMP_APP_NAME}."
export DOMAIN=$( echo ${url:${#prefix}} )
export TEMP_APP_URL="http://$url"

echo "=========================================================="
echo -e "DEPLOYED test blue app ${TEMP_APP_NAME}"
echo -e "on temporary route: ${TEMP_APP_URL}"

# View logs
#cf logs "${TEMP_APP_NAME}" --recent