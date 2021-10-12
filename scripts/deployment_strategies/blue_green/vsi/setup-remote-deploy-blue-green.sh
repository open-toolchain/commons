#!/bin/bash
# This step logs into the Virtual Server Instance based on the credentials provided during the Toolchain creation.
# The step:
#   - Assumes that the upstream task has already downloaded the artifact to the /output location
#   - Carries out all the operation within the home directory of the user i.e. /home/${HOST_USER_NAME}
#   - Copies the artifact from the /output to /home/${HOST_USER_NAME}/app which is defined as WORKDIR
#   - Runs the deploy.sh file as created in the previous step to carry out the step-by-step deployment which may include start/stop of application.

set -e -o pipefail

#source the utility functions
source <(curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/utility.sh")

ProxyCommand=$(checkBastionCredentials $BASTION_HOST_USER_NAME $BASTION_HOST_SSH_KEYS $BASTION_HOST)
if [ $? -eq 1 ]; then
  echo $ProxyCommand
  exit 1
fi

VsiCommand=$(checkVSICredentials "$POOL_USER_NAME" "$POOL_SSH_KEYS")
if [ $? -eq 1 ]; then
  echo $VsiCommand
  exit 1
fi

WORKDIR=/home/${BASTION_HOST_USER_NAME}/app
ibmcloud update -f
ibmcloud plugin install infrastructure-service -v 1.7.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY
curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/cleanup.sh" --output cleanup.sh
if [[ "$BLUE_POOL" == "$GREEN_POOL" ]]; then
  echo "Both Green and Blue pool are same. Please choose the different pools for Blue and Green Enviroment."
  exit 1
fi  
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
    count=$count+1
    LISTNER_POOL_NAME=$GREEN_POOL
  elif [ "$ACTIVE_LISTNER_NAME" == "$GREEN_POOL" ]; then
    count=$count+1
    LISTNER_POOL_NAME=$BLUE_POOL
  fi
done

POOL_ID=$(ibmcloud is load-balancer-pools $LOAD_BALANCER_ID -json | jq -r ".[] | select(.name==\"${LISTNER_POOL_NAME}\") |  .id")
Pool_Member_Id=($(ibmcloud is load-balancer-pool $LOAD_BALANCER_ID $POOL_ID -json | jq -r '.members[].id'))
echo "Load balancer name : $LOAD_BALANCER_NAME"
echo "Backend Pool where app will be deployed is : $LISTNER_POOL_NAME "
echo "---------------------------------------"
for i in "${Pool_Member_Id[@]}"; do
  Pool_Member_IP=$(ibmcloud is load-balancer-pool-member $LOAD_BALANCER_ID $POOL_ID $i -json | jq -r '.target.address')
  installApp
  # Do the health check
  sleep 10
  if ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env VIRTUAL_SERVER_INSTANCE=$Pool_Member_IP "$WORKDIR/health-check.sh" ; then
    echo "Health Check passed."
  else
    exit 1
  fi
  echo "Cleanup of existing app on the host machine."
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' <./cleanup.sh
  echo "---------------------------------------"
done
