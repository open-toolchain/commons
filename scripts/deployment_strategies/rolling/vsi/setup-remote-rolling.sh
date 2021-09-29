#!/bin/bash
# This step logs into the Virtual Server Instance based on the credentials provided during the Toolchain creation.
# The step:
#   - Assumes that the upstream task has already downloaded the artifact to the /output location
#   - Carries out all the operation within the home directory of the user i.e. /home/${HOST_USER_NAME}
#   - Copies the artifact from the /output to /home/${HOST_USER_NAME}/app which is defined as WORKDIR
#   - Runs the deploy.sh file as created in the previous step to carry out the step-by-step deployment which may include start/stop of application.

#source the utility functions
set -eo pipefail
source <(curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/utility.sh")
curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/restore.sh" --output restore.sh
ProxyCommand=$(checkBastionCredentials $BASTION_HOST_USER_NAME $BASTION_HOST_SSH_KEYS $BASTION_HOST)
if [ $? -eq 1 ]; then
  echo $ProxyCommand
  exit 1
fi

VsiCommand=$(checkVSICredentials "$POOL_USER_NAME" "$POOL_SSH_KEYS")
if [ $? -eq 1 ]; then
  echo "$VsiCommand"
  exit 1
fi

WORKDIR=/home/${BASTION_HOST_USER_NAME}/app
ibmcloud plugin install infrastructure-service -v 1.1.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY

LOAD_BALANCER_ID=$(ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\") | .id")
echo "Load balancer name : $LOAD_BALANCER_NAME"
echo "Backend Pool where app will be deployed is : $LB_POOL "
POOL_ID=$(ibmcloud is load-balancer-pools $LOAD_BALANCER_ID -json | jq -r ".[] | select(.name==\"${LB_POOL}\") |  .id")
Pool_Member_Id=($(ibmcloud is load-balancer-pool $LOAD_BALANCER_ID $POOL_ID -json | jq -r '.members[].id'))

deployment_array=()
for i in "${Pool_Member_Id[@]}"; do

  # Update the VSI weight to 0.
  ibmcloud is load-balancer-pool-member-update $LOAD_BALANCER_ID $POOL_ID $i --weight 0

  sleep 120

  Pool_Member_IP=$(ibmcloud is load-balancer-pool-member $LOAD_BALANCER_ID $POOL_ID $i -json | jq -r '.target.address')

  installApp

  # Do the health check
  sleep 10

  if ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env VIRTUAL_SERVER_INSTANCE=$Pool_Member_IP "$WORKDIR/health-check.sh" ; then 
    echo "Health Check passed."
  else  
    echo "Application Health check failed.... do the rollback"

    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env WORKDIR=$WORKDIR 'bash -s' <./restore.sh

    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR "bash $WORKDIR/deploy.sh"

    # update the weight to 100
    ibmcloud is load-balancer-pool-member-update $LOAD_BALANCER_ID $POOL_ID $i --weight 100

    sleep 120
    Deployment_Failed=true
  fi

  if [[ "$Deployment_Failed" ]]; then
    echo "Perform rollback."
    for k in "${deployment_array[@]}"; do

      ibmcloud is load-balancer-pool-member-update $LOAD_BALANCER_ID $POOL_ID $i --weight 0
      sleep 120

      Pool_Member_IP=$(ibmcloud is load-balancer-pool-member $LOAD_BALANCER_ID $POOL_ID $k -json | jq -r '.target.address')

      ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env WORKDIR=$WORKDIR RESTOREFILE=$RESTOREFILE 'bash -s' <./restore.sh

      ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR "bash $WORKDIR/deploy.sh"

      ibmcloud is load-balancer-pool-member-update $LOAD_BALANCER_ID $POOL_ID $i --weight 100
      sleep 120
    done
    echo "Rollback is Done because deployment failed"
    exit 1
  else

    deployment_array+=("$i")

    # update the weight to 100
    ibmcloud is load-balancer-pool-member-update $LOAD_BALANCER_ID $POOL_ID $i --weight 100
    sleep 120
  fi
done

curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/cleanup.sh" --output cleanup.sh
for i in "${Pool_Member_Id[@]}"; do
  Pool_Member_IP=$(ibmcloud is load-balancer-pool-member $LOAD_BALANCER_ID $POOL_ID $i -json | jq -r '.target.address')
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' <./cleanup.sh
done