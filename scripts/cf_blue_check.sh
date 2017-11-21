#!/bin/bash
#set -x
#CF_TRACE=true
max_health_checks=20
expected_response="200"
echo "Check that the new app is ready to serve..."
iterations=0
while [[ "${iterations}" -lt "${max_health_checks}" ]]
do
response=$(curl -sIL -w "%{http_code}" -o /dev/null "${TEMP_APP_URL}")
if [[ "${response}" == "${expected_response}" ]]; then
    echo "Got expected ${response} response"
    break
else
    iterations=$(( iterations + 1 ))
    sleep 3
    echo "Waiting for ${expected_response} response... Got ${response} (${iterations}/${max_health_checks})"
fi
done
if [[ "${iterations}" == "${max_health_checks}" ]]; then
echo "Couldn't get ${expected_response} response. Reverting..."
# Delete temporary route
cf delete-route $DOMAIN -n $TEMP_APP_NAME -f
# Stop temporary app
cf stop $TEMP_APP_NAME
exit 1
fi
echo "##############################################################"
echo "Sanity checked new app $TEMP_APP_NAME"
echo "on temporary route: $TEMP_APP_URL"
echo "##############################################################"