#!/bin/bash

echo "Load balancer name : $LOAD_BALANCER_NAME"
ibmcloud update -f
ibmcloud plugin install infrastructure-service -v 1.7.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY

LOAD_BALANCER_ID=$(ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\") | .id")
POOL_ID=$(ibmcloud is load-balancer-pools "$LOAD_BALANCER_ID" -json | jq -r ".[] | select(.name==\"${LB_POOL}\") |  .id")
ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_1\")" > ig1.json
ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_2\")" > ig2.json
INSTANCE_GROUP_ID1=$(jq -r .id ig1.json)
INSTANCE_GROUP_ID2=$(jq -r .id ig2.json)
Instace_Group_CRN_ID1=$(jq -r .crn ig1.json)
Instace_Group_CRN_ID2=$(jq -r .crn ig2.json)

function abortCanary() {

  Member=($(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$POOL_ID" -json | jq -r '.[]? | .target.address'))
    declare -A Instance
    while IFS= read -r key; do
      ip=$(ibmcloud is in $key -json | jq -r .primary_network_interface.primary_ipv4_address)
      Instance[$ip]=1
    done < <(ibmcloud is igmbrs $canary_ig -json | jq -r '.[].instance.id')
    rm -rf member.json
    touch member.json
    count=0
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
}

if [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:canary" )')" == "null" ]] && [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID2 -json | jq -r '.items[].tags | index( "env:canary" )')" == "null" ]]; then
  echo "Canary app is not deployed."
  exit 0
elif [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:canary" )')" != "null" ]]; then
  canary_ig=$INSTANCE_GROUP_ID1
  canary_crn=$Instace_Group_CRN_ID1
else
  canary_ig=$INSTANCE_GROUP_ID2
  canary_crn=$Instace_Group_CRN_ID2
fi

ibmcloud resource tag-attach --tag-names "canary:abort" --resource-id $canary_crn
sleep 180
sleep $STEP_INTERVAL
abortCanary
ibmcloud resource tag-detach --tag-names "canary:abort" --resource-id $canary_crn