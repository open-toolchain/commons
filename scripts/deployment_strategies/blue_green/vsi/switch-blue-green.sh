#!/bin/bash

ibmcloud update -f
ibmcloud plugin install infrastructure-service -v 1.7.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY

ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\")" > lb.json
LOAD_BALANCER_ID=$(jq -r .id lb.json)
HOSTNAME=$(jq -r .hostname lb.json)
ACTIVE_LISTNER_ID=($(ibmcloud is load-balancer-listeners $LOAD_BALANCER_ID -json | jq -r '.[].default_pool.id' | sort -u))
count=0
for i in "${ACTIVE_LISTNER_ID[@]}"; do
  ACTIVE_LISTNER_NAME=$(ibmcloud is load-balancer-pools $LOAD_BALANCER_ID -json | jq -r ".[] | select(.id==\"$i\") | .name")
  if [[ $count -ge 1 && ("$ACTIVE_LISTNER_NAME" == "$BLUE_POOL" || "$ACTIVE_LISTNER_NAME" == "$GREEN_POOL") ]]; then
    echo "Both the pools are present in the listner. Please update the listner to one pool and re run the pipeline."
  elif [ "$ACTIVE_LISTNER_NAME" == "$BLUE_POOL" ]; then
    OLD_POOL_NAME=$BLUE_POOL
    NEW_POOL_NAME=$GREEN_POOL
  elif [ "$ACTIVE_LISTNER_NAME" == "$GREEN_POOL" ]; then
    OLD_POOL_NAME=$GREEN_POOL
    NEW_POOL_NAME=$BLUE_POOL
  fi
done
echo "Currently active prod backend pool is $OLD_POOL_NAME."
echo "Switching to $NEW_POOL_NAME as prod backend pool."
POOL_ID=$(ibmcloud is load-balancer-pools $LOAD_BALANCER_ID -json | jq -r ".[] | select(.name==\"${NEW_POOL_NAME}\") |  .id")
LOAD_BALANCER_LISTNER_ID=($(ibmcloud is load-balancer-listeners $LOAD_BALANCER_ID -json | jq -r ".[] | select(.default_pool.name==\"$OLD_POOL_NAME\") |.id"))
for i in "${LOAD_BALANCER_LISTNER_ID[@]}"; do
  ibmcloud is load-balancer-listener-update $LOAD_BALANCER_ID $i --default-pool $POOL_ID
  sleep 120
  PORT=$(ibmcloud is lb-l $LOAD_BALANCER_ID $i -json | jq -r .port )
  APP_URL=http://${HOSTNAME}:$PORT
  echo "Application URL is: $APP_URL"
  echo "Java Samaple app example url is : $APP_URL/v1/"
done
