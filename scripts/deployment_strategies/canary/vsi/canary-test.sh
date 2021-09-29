#!/bin/bash

echo "Load balancer name : $LOAD_BALANCER_NAME"
ibmcloud plugin install infrastructure-service -v 1.1.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY

ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\")" > lb.json
LOAD_BALANCER_ID=$(jq -r .id lb.json)
HOSTNAME=$(jq -r .hostname lb.json)
POOL_ID=$(ibmcloud is load-balancer-pools "$LOAD_BALANCER_ID" -json | jq -r ".[] | select(.name==\"${LB_POOL}\") |  .id")
INSTANCE_GROUP_ID1=$(ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_1\") | .id")
INSTANCE_GROUP_ID2=$(ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_2\") | .id")

function perform_test() {
  WEIGHT_SIZE=$1
  if [[ "$(ibmcloud resource search $canary_ig -json | jq -r '.items[].tags | index( "canary:abort" )')" != "null" ]]; then
    echo "Canary deployment abort requested"
    exit 1
  else
    echo "Testing canary deployment..."
    echo "Increasing the weight of canary deployment ${WEIGHT_SIZE}......."
    Member=($(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$POOL_ID" -json | jq -r '.[]? | .target.address'))
    declare -A Instance
    while IFS= read -r key; do
      ip=$(ibmcloud is in $key -json | jq -r .primary_network_interface.primary_ipv4_address)
      Instance[$ip]=1
      echo $Instance[$ip]
    done < <(ibmcloud is igmbrs $canary_ig -json | jq -r '.[].instance.id')
    rm -rf member.json
    touch member.json
    count=0
    for i in "${Member[@]}"; do
      if [ $count == 0 ] && [ ! "${Instance[$i]}" ]; then
        WEIGHT=100-$WEIGHT_SIZE
        ibmcloud is lb-pms $LOAD_BALANCER_ID $POOL_ID -json | jq -r ".[] | select (.target.address==\"$i\").weight=$WEIGHT" | jq -s '.' >member.json
        count=$count+1
      elif [ $count == 0 ]; then
        ibmcloud is lb-pms $LOAD_BALANCER_ID $POOL_ID -json | jq -r ".[] | select (.target.address==\"$i\").weight=$WEIGHT_SIZE" | jq -s '.' >member.json
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
  fi
}

if [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]] && [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID2 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]]; then
  echo "v0 Deployment of the application."
  echo "App is deployed successfully."
  exit 0
elif [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]]; then
  canary_ig=$INSTANCE_GROUP_ID1
  prod_ig=$INSTANCE_GROUP_ID2
else
  canary_ig=$INSTANCE_GROUP_ID2
  prod_ig=$INSTANCE_GROUP_ID1
fi

for ((c = $STEP_SIZE; c <= 100; c = $c + $STEP_SIZE)); do
  echo "Performing canary test $c "
  t=$(($c + $STEP_SIZE))
  if [ "$t" -ge 100 ]; then
    perform_test 100
  else
    perform_test $c
  fi
done

tag_ig_prod $canary_ig
tag_ig_canary $prod_ig
