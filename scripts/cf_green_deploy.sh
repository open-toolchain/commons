#!/bin/bash
# uncomment to debug the script
#set -x
#CF_TRACE=true
# copy the script below into your app code repo (e.g. ./scripts/cf_green_deploy.sh) and 'source' it from your pipeline job
#    source ./scripts/cf_green_deploy.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_green_deploy.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_green_deploy.sh

# BLUE/GREEN DEPLOY STEP 3/3
# Finalizes the blue/green deployment by routing public traffic to the test blue app, deleting the test route, the old green app 
# and renaming the test blue app to be the new green app.
# This script should be run in a CF deploy job, in a stage declaring an env property: BLUE_APP_NAME, BLUE_APP_URL and BLUE_APP_DOMAIN. It will export the new APP_URL

echo "Build environment variables:"
echo "CF_APP=${CF_APP}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "BLUE_APP_NAME=${BLUE_APP_NAME}"
echo "BLUE_APP_URL=${BLUE_APP_URL}"
echo "BLUE_APP_DOMAIN=${BLUE_APP_DOMAIN}"

echo "=========================================================="
echo "DETAILING test blue app"
cf app ${BLUE_APP_NAME}

echo "=========================================================="
echo "MAPPING traffic to the new version by binding to the public host."
cf map-route ${BLUE_APP_NAME} ${BLUE_APP_DOMAIN} -n ${CF_APP}
# NOTE: The old version(s) is still taking traffic to avoid disruption in service.
cf routes | { grep ${BLUE_APP_NAME} || true; }
echo "Deleting the temporary route that was used for testing since it is no longer needed."
cf unmap-route ${BLUE_APP_NAME} ${BLUE_APP_DOMAIN} -n ${BLUE_APP_NAME}
cf delete-route ${BLUE_APP_DOMAIN} -n ${BLUE_APP_NAME} -f
echo "=========================================================="
echo "STOPPING the old green app"
cf delete -f -r ${CF_APP}
echo "=========================================================="
echo "RENAMING the test blue app now it is public. It has become the new green app"
cf rename ${BLUE_APP_NAME} ${CF_APP}
echo "Public routes:"
cf routes | { grep ${CF_APP} || true; }
cf app ${CF_APP}
export APP_URL=http://$(cf app ${CF_APP} | grep -e urls: -e routes: | awk '{print $2}')
echo "=========================================================="
echo -e "SUCCESS ! You have executed a blue/green deployment of ${CF_APP}"
echo -e "at: ${APP_URL}"

# View logs
#cf logs "${CF_APP}" --recent
