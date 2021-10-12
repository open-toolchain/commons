#!/bin/bash

echo "Load balancer name : $LOAD_BALANCER_NAME"
ibmcloud update -f
ibmcloud plugin install infrastructure-service -v 1.7.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY

#source the utility functions
source <(curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/utility.sh")
SLEEP_429=1
ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\")" >lb.json
LOAD_BALANCER_ID=$(jq -r .id lb.json)
HOSTNAME=$(jq -r .hostname lb.json)
LISTNER_ID=$(jq -r .listeners[0].id lb.json)
# Added the sleep to mitigate the rate limiting error.
sleep $SLEEP_429
PORT=$(ibmcloud is lb-l $LOAD_BALANCER_ID $LISTNER_ID -json | jq -r .port)
# Added the sleep to mitigate the rate limiting error.
sleep $SLEEP_429
POOL_ID=$(ibmcloud is load-balancer-pools "$LOAD_BALANCER_ID" -json | jq -r ".[] | select(.name==\"${LB_POOL}\") |  .id")
# Added the sleep to mitigate the rate limiting error.
sleep $SLEEP_429
ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_1\")" >ig1.json
ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_2\")" >ig2.json
INSTANCE_GROUP_ID1=$(jq -r .id ig1.json)
INSTANCE_GROUP_ID2=$(jq -r .id ig2.json)
Instace_Group_CRN_ID1=$(jq -r .crn ig1.json)
Instace_Group_CRN_ID2=$(jq -r .crn ig2.json)

if [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:canary" )')" == "null" ]] && [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID2 -json | jq -r '.items[].tags | index( "env:canary" )')" == "null" ]]; then
  echo "v0 Deployment of the application."
  echo "App is deployed successfully."
  APP_URL=http://${HOSTNAME}:$PORT
  echo "Application URL is: $APP_URL"
  echo "Java Samaple app example url is : $APP_URL/v1/"
  exit 0
elif [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]]; then
  canary_ig=$INSTANCE_GROUP_ID1
  canary_ig_crn=$Instace_Group_CRN_ID1
  prod_ig_crn=$Instace_Group_CRN_ID2
else
  canary_ig=$INSTANCE_GROUP_ID2
  canary_ig_crn=$Instace_Group_CRN_ID2
  prod_ig_crn=$Instace_Group_CRN_ID1
fi

Member=($(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$POOL_ID" -json | jq -r '.[]? | .target.address'))
# Added the sleep to mitigate the rate limiting error.
sleep $SLEEP_429
declare -A Instance
while IFS= read -r key; do
  # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
  ip=$(ibmcloud is in $key -json | jq -r .primary_network_interface.primary_ipv4_address)
  Instance[$ip]=1
  # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
done < <(ibmcloud is igmbrs $canary_ig -json | jq -r '.[].instance.id')

function perform_test() {
  WEIGHT_SIZE=$1
  if [[ "$(ibmcloud resource search $canary_ig -json | jq -r '.items[].tags | index( "canary:abort" )')" != "null" ]]; then
    echo "Canary deployment abort requested"
    exit 1
  else
    echo "Testing canary deployment..."
    echo "Increasing the weight of canary deployment ${WEIGHT_SIZE}......."
    rm -rf member.json
    touch member.json
    count=0
    if [ $(curl -LI ${APP_URL} -o /dev/null -w '%{http_code}\n' -s) == "200" ]; then
      for i in "${Member[@]}"; do
        if [ $count == 0 ] && [ ! "${Instance[$i]}" ]; then
          WEIGHT=100-$WEIGHT_SIZE
          ibmcloud is lb-pms $LOAD_BALANCER_ID $POOL_ID -json | jq -r ".[] | select (.target.address==\"$i\").weight=$WEIGHT" | jq -s '.' >member.json
          # Added the sleep to mitigate the rate limiting error.
          sleep $SLEEP_429
          count=$count+1
        elif [ $count == 0 ]; then
          ibmcloud is lb-pms $LOAD_BALANCER_ID $POOL_ID -json | jq -r ".[] | select (.target.address==\"$i\").weight=$WEIGHT_SIZE" | jq -s '.' >member.json
          # Added the sleep to mitigate the rate limiting error.
          sleep $SLEEP_429
          count=$count+1
        elif [ ! "${Instance[$i]}" ]; then
          WEIGHT=100-$WEIGHT_SIZE
          jq -r ".[] |select (.target.address==\"$i\").weight=$WEIGHT" member.json | jq -s '.' >member1.json
          mv member1.json member.json
        else
          jq -r ".[]| select (.target.address==\"$i\").weight=$WEIGHT_SIZE" member.json | jq -s '.' >member1.json
          mv member1.json member.json
        fi
      done
      ibmcloud is load-balancer-pool-members-update $LOAD_BALANCER_ID $POOL_ID --members "@member.json"
      sleep 120
      sleep $STEP_INTERVAL
    else
      for i in "${Member[@]}"; do
        if [ $count == 0 ] && [ ! "${Instance[$i]}" ]; then
          ibmcloud is lb-pms $LOAD_BALANCER_ID $POOL_ID -json | jq -r ".[] | select (.target.address==\"$i\").weight=100" | jq -s '.' >member.json
          count=$count+1
        elif [ $count == 0 ]; then
          ibmcloud is lb-pms $LOAD_BALANCER_ID $POOL_ID -json | jq -r ".[] | select (.target.address==\"$i\").weight=0" | jq -s '.' >member.json
          count=$count+1
        elif [ ! "${Instance[$i]}" ]; then
          jq -r ".[] |select (.target.address==\"$i\").weight=100" member.json | jq -s '.' >member1.json
          mv member1.json member.json
        else
          jq -r ".[]| select (.target.address==\"$i\").weight=0" member.json | jq -s '.' >member1.json
          mv member1.json member.json
        fi
      done
      ibmcloud is load-balancer-pool-members-update $LOAD_BALANCER_ID $POOL_ID --members "@member.json"
      sleep 120
      echo "Canary tests failed."
      exit 1
    fi
  fi
}

APP_URL=http://${HOSTNAME}:$PORT
for ((c = $STEP_SIZE; c < 100; c = $c + $STEP_SIZE)); do
  echo "Performing canary test $c "
  perform_test $c
done
echo "Performing Final canary test $c "
perform_test 100
tag_ig_prod $canary_ig_crn
tag_ig_canary $prod_ig_crn
echo "App is deployed successfully."
echo "Application URL is: $APP_URL"
echo "Java Samaple app example url is : $APP_URL/v1/"
