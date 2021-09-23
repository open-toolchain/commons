#!/bin/bash
# This step logs into the Virtual Server Instance based on the credentials provided during the Toolchain creation.
# The step:
#   - Assumes that the upstream task has already downloaded the artifact to the /output location
#   - Carries out all the operation within the home directory of the user i.e. /home/${HOST_USER_NAME}
#   - Copies the artifact from the /output to /home/${HOST_USER_NAME}/app which is defined as WORKDIR
#   - Runs the deploy.sh file as created in the previous step to carry out the step-by-step deployment which may include start/stop of application.

set -e -o pipefail
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

WORKDIR=/home/${BASTION_HOST_USER_NAME}/app
echo "Load balancer name : $LOAD_BALANCER_NAME"
ibmcloud plugin install infrastructure-service -v 1.1.0
ibmcloud login -a $API -r $REGION --apikey $APIKEY
############ env ##############
echo "lb-pool : $LB_POOL"
echo "IG1: $INSTANCE_GROUP_1"
echo "IG1: $INSTANCE_GROUP_2"
Health_Port=8080
###############################

LOAD_BALANCER_ID=$(ibmcloud is load-balancers -json | jq -r ".[] | select(.name==\"$LOAD_BALANCER_NAME\") | .id")
Pool_Id=$(ibmcloud is load-balancer-pools "$LOAD_BALANCER_ID" -json | jq -r ".[] | select(.name==\"${LB_POOL}\") |  .id")
Instace_Group_ID1=$(ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_1\") | .id")
Instace_Group_ID2=$(ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_2\") | .id")
Instace_Group_CRN_ID1=$(ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_1\") | .crn")
Instace_Group_CRN_ID2=$(ibmcloud is instance-groups -json | jq -r ".[] | select(.name==\"$INSTANCE_GROUP_2\") | .crn")
Instace_Group1_Count=$(ibmcloud is ig $Instace_Group_ID1 -json | jq -r .membership_count)
Instace_Group2_Count=$(ibmcloud is ig $Instace_Group_ID2 -json | jq -r .membership_count)

Install_App_IG() {

  for j in {1..9}; do
    if [ "$(ibmcloud is instance-group $1 -json | jq -r '.status')" == "healthy" ]; then
      echo "Instance group is scaled up and status is healthy."
      break
    elif [ $j -lt 9 ]; then
      sleep 10
    else
      echo "Instance group status is not healthy."
      exit 1
    fi
  done
  Member_Id=($(ibmcloud is igmbrs $1 -json | jq -r '.[].instance.id'))
  for i in "${Member_Id[@]}"; do
    WORKDIR=/home/${BASTION_HOST_USER_NAME}/app
    echo "Member Id is : $i"
    Pool_Member_IP=$(ibmcloud is in $i -json | jq -r .primary_network_interface.primary_ipv4_address)
    echo "Removing the existing artifacts from the host machine and taking backup.."
    BUILDDIR="/home/${POOL_USER_NAME}/${PIPELINERUNID}"
    DEPLOY_SCRIPT_PATH="./scripts-repo/${subpath}/deploy.sh"

    echo "Creating Build Directory [$BUILDDIR]"

    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP "mkdir -p ${BUILDDIR}"

    echo "Copying the artifacts and deploy script to the host machine."
    scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${OBJECTNAME} $POOL_USER_NAME@$Pool_Member_IP:${BUILDDIR}

    scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${DEPLOY_SCRIPT_PATH} $POOL_USER_NAME@$Pool_Member_IP:${BUILDDIR}

    echo "Extract the new artifacts in the host machine."
    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $POOL_USER_NAME@$Pool_Member_IP env BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME BUILDDIR=$BUILDDIR " pwd ; cd ${BUILDDIR} ; tar -xf ${OBJECTNAME} ; rm ${OBJECTNAME} "

    echo "Take the backup of existing app on the host machine."
    curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/backup.sh" --output backup.sh
    ssh -i vsi.key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' < ./backup.sh
 
    echo "Login to the Virtual Machine and process the deployment."
    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" \
      $POOL_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME "bash /$WORKDIR/deploy.sh"

    echo "Cleanup of existing app on the host machine."
    curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/cleanup.sh" --output cleanup.sh
    ssh -i vsi.key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' < ./cleanup.sh

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
        echo "Application Health check failed. Canary deployment is failded."
        exit 1
      fi
    done
  done
}

tag_ig_prod() {
  echo "Tag IG to the 'env:prod'"
  ibmcloud resource tag-attach --tag-names "env:prod" --resource-id "$1"
  ibmcloud resource tag-detach --tag-names "env:canary" --resource-id "$1"
}

tag_ig_canary() {
  echo "Tag IG to the 'env:canary'"
  ibmcloud resource tag-attach --tag-names "env:canary" --resource-id "$1"
  ibmcloud resource tag-detach --tag-names "env:prod" --resource-id "$1"
}

attach_to_lb() {
  echo "Attach Instances to the pool"
  declare -A Member
  while IFS= read -r key; do
    Member[$key]=1
  done < <(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$Pool_Id" -json | jq -r '.[]? | .target.address')
  Instance_Id=($(ibmcloud is igmbrs $1 -json | jq -r '.[].instance.id'))
  for i in "${Instance_Id[@]}"; do
    echo "Check if Instance is already in the pool"
    Pool_Member_IP=$(ibmcloud is in $i -json | jq -r .primary_network_interface.primary_ipv4_address)
    echo "${Member[$Pool_Member_IP]}"
    echo "$Pool_Member_IP"
    if [ ! "${Member[$Pool_Member_IP]}" ]; then
      ibmcloud is load-balancer-pool-member-create "$LOAD_BALANCER_ID" "$Pool_Id" $Health_Port "$Pool_Member_IP" --weight "$2"
    else
      echo "Update the Member weight"
      Pool_Member_ID=$(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$Pool_Id" -json | jq -r ".[] | select(.target.address==\"$Pool_Member_IP\") | .id ")
      ibmcloud is load-balancer-pool-member-update "$LOAD_BALANCER_ID" "$Pool_Id" "$Pool_Member_ID" --weight "$2"
    fi
    sleep 120
  done
}

if [[ "$(ibmcloud is load-balancer-pool $LOAD_BALANCER_ID $Pool_Id -json | jq -r '.members | .[]? |.id')" == "" ]]; then
  echo "v0 Deployment of the application."
  if [[ $Instace_Group2_Count -gt $Instace_Group1_Count ]]; then
    prod_ig=$Instace_Group_ID2
    prod_ig_crn=$Instace_Group_CRN_ID2
  else
    prod_ig=$Instace_Group_ID1
    prod_ig_crn=$Instace_Group_CRN_ID1
  fi
  Install_App_IG "$prod_ig"
  tag_ig_prod "$prod_ig_crn"
  attach_to_lb "$prod_ig" 100
  echo "App is deployed successfully."
  exit 0
fi

if [[ "$(ibmcloud resource search $Instace_Group_ID1 -json | jq -r '.items[].tags | index( "env:prod" )')" == "null" ]]; then
  echo "test"
  prod_ig=$Instace_Group_ID2
  canary_ig=$Instace_Group_ID1
  prod_ig_crn=$Instace_Group_CRN_ID2
  canary_ig_crn=$Instace_Group_CRN_ID1
  canary_Count=$Instace_Group2_Count
else
  prod_ig=$Instace_Group_ID1
  canary_ig=$Instace_Group_ID2
  prod_ig_crn=$Instace_Group_CRN_ID1
  canary_ig_crn=$Instace_Group_CRN_ID2
  canary_Count=$Instace_Group1_Count
fi

echo "Scale up the instances in the canary instance group"
ibmcloud is instance-group-update "$canary_ig" --membership-count=$canary_Count
echo "check the health of the instances"
Install_App_IG "$canary_ig"
attach_to_lb "$canary_ig" 0
tag_ig_prod "$prod_ig_crn"
tag_ig_canary "$canary_ig_crn"
echo "App is deployed successfully."

echo "Canary test "
echo $ACCEPTANCE_TEST_URL

function perform_test() {
  WEIGHT_SIZE=$1
  if [[ "$(ibmcloud resource search $canary_ig -json | jq -r '.items[].tags | index( "canary:abort" )')" != "null" ]]; then
    echo "Canary deployment abort requested"
    exit 1
  else
    echo "Testing canary deployment..."
    echo "Increasing the weight of canary deployment ${WEIGHT_SIZE}......."
    Member=($(ibmcloud is lb-pms "$LOAD_BALANCER_ID" "$Pool_Id" -json | jq -r '.[]? | .target.address'))
    declare -A Instance
    while IFS= read -r key; do
      echo $key
      ip=$(ibmcloud is in $key -json | jq -r .primary_network_interface.primary_ipv4_address)
      echo $ip
      Instance[$ip]=1
      echo $Instance[$ip]
    done < <(ibmcloud is igmbrs $canary_ig -json | jq -r '.[].instance.id')
    rm -rf member.json
    touch member.json
    count=0
    for i in "${Member[@]}"; do
      if [ $count == 0 ] && [ ! "${Instance[$i]}" ]; then
        WEIGHT=100-$WEIGHT_SIZE
        ibmcloud is lb-pms $LOAD_BALANCER_ID $Pool_Id -json | jq -r ".[] | select (.target.address==\"$i\").weight=$WEIGHT" | jq -s '.' >member.json
        count=$count+1
      elif [ $count == 0 ]; then
        ibmcloud is lb-pms $LOAD_BALANCER_ID $Pool_Id -json | jq -r ".[] | select (.target.address==\"$i\").weight=$WEIGHT_SIZE" | jq -s '.' >member.json
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
    cat member.json
    ibmcloud is load-balancer-pool-members-update $LOAD_BALANCER_ID $Pool_Id --members "@member.json"
    sleep 120
    sleep $STEP_INTERVAL
  fi
}

for ((c = $STEP_SIZE; c <= 100; c = $c + $STEP_SIZE)); do
  echo "Performing canary test $c "
  t=$(($c + $STEP_SIZE))
  if [ "$t" -ge 100 ]; then
    perform_test 100
  else
    perform_test $c
  fi
done
