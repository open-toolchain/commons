#!/bin/bash
# uncomment to debug the script
#set -x
#CF_TRACE=true
# copy the script below into your app code repo (e.g. ./scripts/cf_blue_deploy.sh) and 'source' it from your pipeline job
#    source ./scripts/cf_blue_deploy.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_blue_deploy.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_blue_deploy.sh

# BLUE/GREEN DEPLOY STEP 1/3
# Deploys a Cloud Foundry app on a test route, and exports the test app url
# This script should be run in a CF deploy job, in a stage declaring env properties: BLUE_APP_NAME, BLUE_APP_URL and BLUE_APP_DOMAIN

echo "Build environment variables:"
echo "CF_APP=${CF_APP}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://cloud.ibm.com/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

# Compute a unique app name using the reserved CF_APP name (configured in the 
# deployer or from the manifest.yml file), the build number, and a 
# timestamp (allowing multiple deploys for the same build).
export BLUE_APP_NAME="${CF_APP}-${BUILD_NUMBER}-$(date +%s)"

echo "=========================================================="
echo -e "DEPLOYING test blue app: ${BLUE_APP_NAME}"
# push and start the application, granting it 180s for app to fully start
cf push ${BLUE_APP_NAME} -t 180
# alternatively, if you need to set env properties, use the commands below instead
# cf push ${BLUE_APP_NAME} --no-start
# cf set-env $BLUE_APP_NAME <property> <value>
# cf start ${BLUE_APP_NAME}

# retrieve the temp app domain and url
cf apps | grep ${BLUE_APP_NAME}
URL=$(cf app ${BLUE_APP_NAME} | grep -e urls: -e routes: | awk '{print $2}')
PREFIX="${BLUE_APP_NAME}."
export BLUE_APP_DOMAIN=$( echo ${URL:${#PREFIX}} )
export BLUE_APP_URL="http://$URL"

echo "=========================================================="
echo -e "DEPLOYED test blue app ${BLUE_APP_NAME}"
echo -e "at: ${BLUE_APP_URL}"
echo ""
echo "Exported stage environment variables:"
echo "BLUE_APP_NAME=${BLUE_APP_NAME}"
echo "BLUE_APP_URL=${BLUE_APP_URL}"
echo "BLUE_APP_DOMAIN=${BLUE_APP_DOMAIN}"

# View logs
#cf logs "${BLUE_APP_NAME}" --recent