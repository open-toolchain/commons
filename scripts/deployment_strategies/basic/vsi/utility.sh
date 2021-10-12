#!/bin/bash

function checkVSICredentials() {

    if [[ -z "$1" ]]; then
        echo "Please provide User name to log on to Virtual Server Instance"
        return 1
    elif [[ -n "$2" ]]; then
        touch vsi.key
        chmod 600 vsi.key
        echo $2 | base64 -d >vsi.key
        VsiCommand="-o LogLevel=ERROR -i vsi.key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        echo $VsiCommand
    else
        echo "Please provide either SSH Password or SSH Key provided to log on to Virtual Server Instance."
        return 1
    fi

}

function checkBastionCredentials() {

    if [[ -z "$1" ]]; then
        echo "Please provide User name to log on to Virtual Server Instance"
        return 1
    elif [[ -n "$2" ]]; then
        touch bastion.key
        echo $2 | base64 -d >bastion.key
        chmod 600 bastion.key
        ProxyCommand="ssh  -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i bastion.key -W %h:%p $1@$3"
        echo $ProxyCommand
    else
        echo "Please provide either SSH Password or SSH Key provided to log on to Virtual Server Instance."
        return 1
    fi

}

function installApp() {

    BUILDDIR=/home/${BASTION_HOST_USER_NAME}/${PIPELINERUNID}
    DEPLOY_SCRIPT_PATH="./scripts-repo/${subpath}/deploy.sh"
    HEALTH_SCRIPT_PATH="./scripts-repo/${subpath}/health-check.sh"
    chmod 777 "./scripts-repo/${subpath}/health-check.sh"
    echo "Creating Build Directory [$BUILDDIR]"
    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP "mkdir -p ${BUILDDIR}"

    echo "Copying the artifacts to the host machine."
    scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${OBJECTNAME} $BASTION_HOST_USER_NAME@$Pool_Member_IP:${BUILDDIR}

    echo "Copying the deploy script on the host machine."
    scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${DEPLOY_SCRIPT_PATH} $BASTION_HOST_USER_NAME@$Pool_Member_IP:${BUILDDIR}
    scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${HEALTH_SCRIPT_PATH} $BASTION_HOST_USER_NAME@$Pool_Member_IP:${BUILDDIR}
    echo "Extract the new artifacts in the host machine."
    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME BUILDDIR=$BUILDDIR " pwd ; cd ${BUILDDIR} ; tar -xf ${OBJECTNAME} ; rm ${OBJECTNAME} "

    echo "Take the backup of existing app on the host machine."
    curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/backup.sh" --output backup.sh
    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" $BASTION_HOST_USER_NAME@$Pool_Member_IP env PIPELINERUNID=$PIPELINERUNID BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR 'bash -s' <./backup.sh
    echo "Login to the Virtual Machine and process the deployment."
    ssh $VsiCommand -o ProxyCommand="$ProxyCommand" \
        $BASTION_HOST_USER_NAME@$Pool_Member_IP env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR BASTION_HOST_USER_NAME=$BASTION_HOST_USER_NAME "bash /$WORKDIR/deploy.sh"

}

function IGhealthCheck() {
  for j in {1..9}; do
    if [ "$(ibmcloud is instance-group $1 -json | jq -r '.status')" == "healthy" ]; then
      echo "Instance group status is healthy."
      break
    elif [ $j -lt 9 ]; then
      sleep 10
    else
      echo "Instance group status is not healthy."
      exit 1
    fi
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
