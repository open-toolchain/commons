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
elif [[ ! -z "$BASTION_HOST_SSH_KEYS" ]]; then
  echo "Using SSH Key to log on to Virtual Server Instance"
  echo $BASTION_HOST_SSH_KEYS | base64 -d >bastion.key
  chmod 400 bastion.key
  ProxyCommand="ssh  -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i bastion.key -W %h:%p $BASTION_HOST_USER_NAME@${BASTION_HOST}"
else
  echo "Please provide SSH Key to log on to Bastion Host Instance."
  exit 1
fi

if [[ -z "$POOL_USER_NAME" ]]; then
  echo "Please provide User name to log on to Virtual Server Instance"
  exit 1
elif [[ ! -z "$POOL_SSH_KEYS" ]]; then
  echo "Using SSH Key to log on to Virtual Server Instance"
  echo $POOL_SSH_KEYS | base64 -d >vsi.key
  chmod 400 vsi.key
  VsiCommand="-o LogLevel=ERROR -i vsi.key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
else
  echo "Please provide SSH Key to log on to Virtual Server Instance."
  exit 1
fi

LOAD_BALANCER_ID=$(ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\") | .id")
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

Pool_Id=$(ibmcloud is load-balancer-pools $LOAD_BALANCER_ID -json | jq -r ".[] | select(.name==\"${LISTNER_POOL_NAME}\") |  .id")
Pool_Member_Id=($(ibmcloud is load-balancer-pool $LOAD_BALANCER_ID $Pool_Id -json | jq -r '.members[].id'))
echo "Load balancer name : $LOAD_BALANCER_NAME"
echo "Backend Pool where app will be deployed is : $LISTNER_POOL_NAME "
echo "---------------------------------------"
for i in "${Pool_Member_Id[@]}"; do
  Pool_Member_IP=$(ibmcloud is load-balancer-pool-member $LOAD_BALANCER_ID $Pool_Id $i -json | jq -r '.target.address')
  echo "Ip: $Pool_Member_IP"
  echo "Removing the existing artifacts from the host machine and taking backup.."
  echo "$ProxyCommand"
  BUILDDIR=/home/${BASTION_HOST_USER_NAME}/${PIPELINERUNID}
  DEPLOY_SCRIPT_PATH="./scripts-repo/${subpath}/deploy.sh"
  echo "Creating Build Directory [$BUILDDIR]"
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP "mkdir -p ${BUILDDIR}"

  echo "Copying the artifacts to the host machine."
  scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${OBJECTNAME} $BASTION_HOST_USER_NAME@$Pool_Member_IP:${BUILDDIR}

  echo "Copying the deploy script on the host machine."
  scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${DEPLOY_SCRIPT_PATH} $BASTION_HOST_USER_NAME@$Pool_Member_IP:${BUILDDIR}

  echo "Extract the new artifacts in the host machine."
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME BUILDDIR=$BUILDDIR " pwd ; cd ${BUILDDIR} ; tar -xf ${OBJECTNAME} ; rm ${OBJECTNAME} "

  echo "Take the backup of existing app on the host machine."
  curl -sSL "$(params.commons-hosted-region)/scripts/deployment_strategies/basic/vsi/backup.sh" --output backup.sh
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' < ./backup.sh
  echo "Login to the Virtual Machine and process the deployment."
  ssh $VsiCommand -o ProxyCommand="$ProxyCommand" \
    $BASTION_HOST_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME "bash /$WORKDIR/deploy.sh"

  echo "Cleanup of existing app on the host machine."
  curl -sSL "$(params.commons-hosted-region)/scripts/deployment_strategies/basic/vsi/cleanup.sh" --output cleanup.sh
  ssh $VsiCommand-o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' < ./cleanup.sh
  echo "---------------------------------------"
done
