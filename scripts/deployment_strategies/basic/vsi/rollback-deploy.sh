#!/bin/bash
BACKUPDIR=${WORKDIR}_backup
echo "WORKDIR is [$WORKDIR]"
echo "BACKUPDIR is [$BACKUPDIR]"
source <(curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/utility.sh")

VsiCommand=$(checkVSICredentials "$HOST_USER_NAME" "$HOST_SSH_KEYS")
if [ $? -eq 1 ]; then
    echo $VsiCommand
    exit 1
fi

echo "Tasks has failed, Performing Rollback."
curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/restore.sh" --output restore.sh
ssh $VsiCommand -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env HOST_USER_NAME=$HOST_USER_NAME WORKDIR=$WORKDIR 'bash -s' < ./restore.sh

ssh $VsiCommand -o StrictHostKeyChecking=no \
    $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR HOST_USER_NAME=$HOST_USER_NAME "bash /$WORKDIR/deploy.sh"
