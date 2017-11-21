#!/bin/bash
#set -x
#CF_TRACE=true
# Compute a unique app name using the reserved CF_APP name (configured in the 
# deployer or from the manifest.yml file), the build number, and a 
# timestamp (allowing multiple deploys for the same build).
export TEMP_APP_NAME="${CF_APP_NAME}-${BUILD_NUMBER}-$(date +%s)"
echo "Pushing new app:$TEMP_APP_NAME"
cf push $TEMP_APP_NAME --no-start
cf set-env $TEMP_APP_NAME WORKSPACE_ID $WORKSPACE_ID
cf start $TEMP_APP_NAME
cf apps | grep $TEMP_APP_NAME
url=$(cf app $TEMP_APP_NAME | grep urls: | awk '{print $2}')
prefix="${TEMP_APP_NAME}."
export DOMAIN=$( echo ${url:${#prefix}} )
export TEMP_APP_URL="http://$url"
echo "##############################################################"
echo "Deployed new app $TEMP_APP_NAME"
echo "on temporary route: $TEMP_APP_URL"
echo "##############################################################"
# View logs
#cf logs "${TEMP_APP_NAME}" --recent