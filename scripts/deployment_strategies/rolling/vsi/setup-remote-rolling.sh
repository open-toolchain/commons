#!/bin/bash
# This step logs into the Virtual Server Instance based on the credentials provided during the Toolchain creation.
# The step:
#   - Assumes that the upstream task has already downloaded the artifact to the /output location
#   - Carries out all the operation within the home directory of the user i.e. /home/${HOST_USER_NAME}
#   - Copies the artifact from the /output to /home/${HOST_USER_NAME}/app which is defined as WORKDIR
#   - Runs the deploy.sh file as created in the previous step to carry out the step-by-step deployment which may include start/stop of application.

set -e -o pipefail
WORKDIR=/home/${BASTION_HOST_USER_NAME}/app
ibmcloud plugin install infrastructure-service -v 1.1.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY

if [[ -z "$BASTION_HOST_USER_NAME" ]]; then
  echo "Please provide User name to log on to Virtual Server Instance"
  exit 1
elif [[ -n "$BASTION_HOST_SSH_KEYS" ]]; then
  echo "Using SSH Key to log on to Virtual Server Instance"
  echo $BASTION_HOST_SSH_KEYS | base64 -d >bastion.key
  chmod 400 bastion.key
  ProxyCommand="ssh  -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i bastion.key -W %h:%p $BASTION_HOST_USER_NAME@${BASTION_HOST}"
else
  echo "Please provide SSH Key provided to log on to Virtual Server Instance."
  exit 1
fi

if [[ -z "$POOL_USER_NAME" ]]; then
  echo "Please provide User name to log on to Virtual Server Instance"
  exit 1
elif [[ -n "$POOL_SSH_KEYS" ]]; then
  echo "Using SSH Key to log on to Virtual Server Instance"
  echo $POOL_SSH_KEYS | base64 -d >vsi.key
  chmod 400 vsi.key
  VsiCommand="-o LogLevel=ERROR -i vsi.key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
else
  echo "Please provide either SSH Password or SSH Key provided to log on to Virtual Server Instance."
  exit 1
fi

LOAD_BALANCER_ID=$(ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\") | .id")
echo "Load balancer name : $LOAD_BALANCER_NAME"
echo "Backend Pool where app will be deployed is : $LB_POOL "
Pool_Id=$(ibmcloud is load-balancer-pools $LOAD_BALANCER_ID -json | jq -r ".[] | select(.name==\"${LB_POOL}\") |  .id")
Pool_Member_Id=($(ibmcloud is load-balancer-pool $LOAD_BALANCER_ID $Pool_Id -json | jq -r '.members[].id'))

count=0
deployment_array=()
for i in "${Pool_Member_Id[@]}"; do
  # Get the Pool member data.
  echo $(ibmcloud is load-balancer-pool-members $LOAD_BALANCER_ID $Pool_Id -json | jq ".[$count].weight = 0 ") >member1.json

  # Update the VSI weight to 0.
  ibmcloud is load-balancer-pool-members-update $LOAD_BALANCER_ID $Pool_Id --members @member1.json

  sleep 120

  Pool_Member_IP=$(ibmcloud is load-balancer-pool-member $LOAD_BALANCER_ID $Pool_Id $i -json | jq -r '.target.address')

  echo "Removing the existing artifacts from the host machine and taking backup.."
  BUILDDIR=/home/${POOL_USER_NAME}/${PIPELINERUNID}
  DEPLOY_SCRIPT_PATH="./scripts-repo/${subpath}/deploy.sh"

  echo "Creating Build Directory [$BUILDDIR]"

  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP "mkdir -p ${BUILDDIR}"

  echo "Copying the artifacts and deploy script to the host machine."
  scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${OBJECTNAME} $POOL_USER_NAME@$Pool_Member_IP:${BUILDDIR}

  scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${DEPLOY_SCRIPT_PATH} $POOL_USER_NAME@$Pool_Member_IP:${BUILDDIR}

  echo "Extract the new artifacts in the host machine."
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME BUILDDIR=$BUILDDIR " pwd ; cd ${BUILDDIR} ; tar -xf ${OBJECTNAME} ; rm ${OBJECTNAME} "

  echo "Take the backup of existing app on the host machine."
  curl -sSL "$(params.commons-hosted-region)/scripts/deployment_strategies/basic/vsi/backup.sh" --output backup.sh
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' < ./backup.sh

  echo "Login to the Virtual Machine and process the deployment."
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" \
    $POOL_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME "bash /$WORKDIR/deploy.sh"

  # Do the health check
  sleep 10

  for j in {1..5}; do
    echo "Doing Health check. Attempt Number: ${j}"
    if [ "$(ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP curl -s --head -w "%{http_code}" http://${Pool_Member_IP}:8080/health/ -o /dev/null)" == "200" ]; then
      echo "App Health Check passed..."
      break
    elif [ $j -lt 5 ]; then
      sleep 1
    else
      echo "Application Health check failed.... do the rollback"

      ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env WORKDIR=$WORKDIR RESTOREFILE=$RESTOREFILE 'bash -s' < ./scripts-repo/${subpath}/restore.sh

      ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR "bash /$WORKDIR/deploy.sh"
      # get the pool memeber data
      echo $(ibmcloud is load-balancer-pool-members $LOAD_BALANCER_ID $Pool_Id -json | jq ".[$count].weight = 100 ") >member1.json
      # update the weight to 100
      ibmcloud is load-balancer-pool-members-update $LOAD_BALANCER_ID $Pool_Id --members @member1.json

      sleep 120
      Deployment_Failed=true
    fi
  done

  curl -sSL "$(params.commons-hosted-region)/scripts/deployment_strategies/basic/vsi/restore.sh" --output restore.sh
  if [[ "$Deployment_Failed" ]]; then
    echo "Do rollback"
    for k in "${deployment_array[@]}"; do

      Pool_Member_IP=$(ibmcloud is load-balancer-pool-member $LOAD_BALANCER_ID $Pool_Id $k -json | jq -r '.target.address')
      
      ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env WORKDIR=$WORKDIR RESTOREFILE=$RESTOREFILE 'bash -s' < ./restore.sh

      ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR "bash /$WORKDIR/deploy.sh"
    done
    echo "Rollback is Done because deployment failed"
    exit 1
  else

    deployment_array+=("$i")
    # get the pool memeber data
    echo $(ibmcloud is load-balancer-pool-members $LOAD_BALANCER_ID $Pool_Id -json | jq ".[$count].weight = 100 ") >member1.json

    # update the weight to 100
    ibmcloud is load-balancer-pool-members-update $LOAD_BALANCER_ID $Pool_Id --members @member1.json
    sleep 120
    count=$count+1
  fi
done
