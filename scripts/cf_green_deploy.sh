#!/bin/bash
#set -x
#CF_TRACE=true
cf app $TEMP_APP_NAME
# Map traffic to the new version by binding to the public host.
# NOTE: The old version(s) is still taking traffic to avoid disruption in service.
cf map-route $TEMP_APP_NAME $DOMAIN -n $CF_APP_NAME
cf routes | { grep $TEMP_APP_NAME || true; }
# Delete the temporary route that was used for testing since it is no longer needed.
cf unmap-route $TEMP_APP_NAME $DOMAIN -n $TEMP_APP_NAME
cf delete-route $DOMAIN -n $TEMP_APP_NAME -f
# Delete the old app at this point. They are no longer needed.
cf delete -f -r $CF_APP_NAME
# Rename temp app now it is public
cf rename $TEMP_APP_NAME $CF_APP_NAME
echo "Public route bindings:"
cf routes | { grep $CF_APP_NAME || true; }
cf app $CF_APP_NAME
export APP_URL=http://$(cf app $CF_APP_NAME | grep urls: | awk '{print $2}')
echo "##############################################################"
echo "You have successfully executed a rolling deployment of $CF_APP_NAME"
echo "at: $APP_URL"
echo "##############################################################"
# View logs
#cf logs "${CF_APP_NAME}" --recent