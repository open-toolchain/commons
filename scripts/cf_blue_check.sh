#!/bin/bash
# uncomment to debug the script
#set -x
#CF_TRACE=true
# copy the script below into your app code repo (e.g. ./scripts/cf_blue_deploy.sh) and 'source' it from your pipeline job
#    source ./scripts/cf_blue_deploy.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_blue_deploy.sh")`
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_blue_deploy.sh

# BLUE/GREEN DEPLOY STEP 2/3
# Verifies that test blue app is actually running. Typically this job would be followed by other functional test jobs 
# targeting $TEMP_APP_URL. 
# This script should be run in a CF test job, in a stage declaring an env property: TEMP_APP_URL (set beforehand)

echo "Build environment variables:"
echo "CF_APP_NAME=${CF_APP_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "CF_APP_NAME=${CF_APP_NAME}"
echo "TEMP_APP_URL=${TEMP_APP_URL}"

# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

MAX_HEALTH_CHECKS=20
EXPECTED_RESPONSE="200"
echo "=========================================================="
echo "SANITY CHECKING that the test blue app is ready to serve..."
COUNT=0
while [[ "${COUNT}" -lt "${MAX_HEALTH_CHECKS}" ]]
do
RESPONSE=$(curl -sIL -w "%{http_code}" -o /dev/null "${TEMP_APP_URL}")
if [[ "${RESPONSE}" == "${EXPECTED_RESPONSE}" ]]; then
    echo -e "Got expected ${RESPONSE} RESPONSE"
    break
else
    COUNT=$(( COUNT + 1 ))
    sleep 3
    echo -e "Waiting for response: ${EXPECTED_RESPONSE} ... Got ${RESPONSE} (${COUNT}/${MAX_HEALTH_CHECKS})"
fi
done
if [[ "${COUNT}" == "${MAX_HEALTH_CHECKS}" ]]; then
  echo "Couldn't get ${EXPECTED_RESPONSE} RESPONSE. Discarding test blue app..."
  # Delete temporary route
  cf delete-route $DOMAIN -n $TEMP_APP_NAME -f
  # Stop temporary app
  cf stop $TEMP_APP_NAME
  exit 1
fi
echo "=========================================================="
echo -e "SANITY CHECKED test blue app ${TEMP_APP_NAME}"
echo -e "on temporary route: ${TEMP_APP_URL}"
echo "##############################################################"