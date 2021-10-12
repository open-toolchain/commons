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
SLEEP_429=1
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

if [[ "$INSTANCE_GROUP_1" == "$INSTANCE_GROUP_2" ]]; then
  echo "Both Instance group is same. Please choose the different instance group for prod and canary enviroment."
  exit 1
fi 

WORKDIR=/home/${BASTION_HOST_USER_NAME}/app
echo "Load balancer name : $LOAD_BALANCER_NAME"
ibmcloud update -f
ibmcloud plugin install infrastructure-service -v 1.7.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY

ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\")" > lb.json
LOAD_BALANCER_ID=$(jq -r .id lb.json)
HOSTNAME=$(jq -r .hostname lb.json)
LISTNER_ID=$(jq -r .listeners[0].id lb.json)
  # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
PORT=$(ibmcloud is lb-l $LOAD_BALANCER_ID $LISTNER_ID -json | jq -r .port )
  # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
POOL_ID=$(ibmcloud is load-balancer-pools "$LOAD_BALANCER_ID" -json | jq -r ".[] | select(.name==\"${LB_POOL}\") |  .id")
  # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_1\")" > ig1.json
  # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_2\")" > ig2.json
INSTANCE_GROUP_ID1=$(jq -r .id ig1.json)
INSTANCE_GROUP_ID2=$(jq -r .id ig2.json)
Instace_Group_CRN_ID1=$(jq -r .crn ig1.json)
Instace_Group_CRN_ID2=$(jq -r .crn ig2.json)
Instace_Group1_Count=$(jq -r .membership_count ig1.json)
Instace_Group2_Count=$(jq -r .membership_count ig2.json)

Install_App_IG() {
  curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/cleanup.sh" --output cleanup.sh
  Member_Id=($(ibmcloud is igmbrs $1 -json | jq -r '.[].instance.id'))
    # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
  for i in "${Member_Id[@]}"; do
    WORKDIR=/home/${BASTION_HOST_USER_NAME}/app
    echo "Member Id is : $i"
    Pool_Member_IP=$(ibmcloud is in $i -json | jq -r .primary_network_interface.primary_ipv4_address)

    installApp
    
    echo "Cleanup of existing app on the host machine."
    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' <./cleanup.sh
    
    # Do the health check
    sleep 10
    if ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env VIRTUAL_SERVER_INSTANCE=$Pool_Member_IP "$WORKDIR/health-check.sh" ; then 
      echo "Health Check passed."
    else 
      exit 1  
    fi
  done
}

attach_to_lb() {
  echo "Attach Instances to the pool"
  declare -A Member
  while IFS= read -r key; do
    # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
    Member[$key]=1
  done < <(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$POOL_ID" -json | jq -r '.[]? | .target.address')
  Instance_Id=($(ibmcloud is igmbrs $1 -json | jq -r '.[].instance.id'))
    # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
  for i in "${Instance_Id[@]}"; do
    echo "Check if Instance is already in the pool"
    Pool_Member_IP=$(ibmcloud is in $i -json | jq -r .primary_network_interface.primary_ipv4_address)
      # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
    if [ ! "${Member[$Pool_Member_IP]}" ]; then
      ibmcloud is load-balancer-pool-member-create "$LOAD_BALANCER_ID" "$POOL_ID" $PORT "$Pool_Member_IP" --weight $2
    else
      echo "Update the Member weight to : $2"
      Pool_Member_ID=$(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$POOL_ID" -json | jq -r ".[] | select(.target.address==\"$Pool_Member_IP\") | .id ")
        # Added the sleep to mitigate the rate limiting error.
  sleep $SLEEP_429
      ibmcloud is load-balancer-pool-member-update "$LOAD_BALANCER_ID" "$POOL_ID" "$Pool_Member_ID" --weight $2
    fi
    sleep 120
  done
}

if [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]] && [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID2 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]]; then
  echo "v0 Deployment of the application."
  Install_App_IG "$INSTANCE_GROUP_ID1"
  tag_ig_prod "$Instace_Group_CRN_ID1"
  attach_to_lb "$INSTANCE_GROUP_ID1" 100
  attach_to_lb "$INSTANCE_GROUP_ID2" 0
  echo "App is deployed successfully."
  exit 0

elif [[ "$(ibmcloud resource search $INSTANCE_GROUP_ID1 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]]; then
  echo "test"
  canary_ig=$INSTANCE_GROUP_ID1
  prod_ig_crn=$Instace_Group_CRN_ID2
  canary_ig_crn=$Instace_Group_CRN_ID1
  canary_Count=$Instace_Group2_Count

else
  canary_ig=$INSTANCE_GROUP_ID2
  prod_ig_crn=$Instace_Group_CRN_ID1
  canary_ig_crn=$Instace_Group_CRN_ID2
  canary_Count=$Instace_Group1_Count
fi

echo "Scale up the instances in the canary instance group"
ibmcloud is instance-group-update "$canary_ig" --membership-count=$canary_Count
echo "check the health of the instances"
IGhealthCheck "$canary_ig"
Install_App_IG "$canary_ig"
attach_to_lb "$canary_ig" 0
tag_ig_prod "$prod_ig_crn"
tag_ig_canary "$canary_ig_crn"
echo "App is deployed successfully."
