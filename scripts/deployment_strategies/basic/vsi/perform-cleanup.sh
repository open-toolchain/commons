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
curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/cleanup.sh" --output cleanup.sh
ssh $VsiCommand -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env RESTOREFILE=$RESTOREFILE HOST_USER_NAME=$HOST_USER_NAME 'bash -s' < ./cleanup.sh
