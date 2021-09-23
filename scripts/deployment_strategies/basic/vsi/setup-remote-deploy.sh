#!/bin/bash
set -e -o pipefail

# This step logs into the Virtual Server Instance based on the credentials provided during the Toolchain creation.
# The step:
#   - Assumes that the upstream task has already downloaded the artifact to the /output location
#   - Carries out all the operation within the home directory of the user i.e. /home/${HOST_USER_NAME}
#   - Copies the artifact from the /output to /home/${HOST_USER_NAME}/app which is defined as WORKDIR
#   - Runs the deploy.sh file as created in the previous step to carry out the step-by-step deployment which may include start/stop of application.

if [[ -z "$HOST_USER_NAME" ]]; then
    echo "Please provide User name to log on to Virtual Server Instance"
    exit 1
elif [[ -n "$HOST_PASSWORD" ]]; then
    echo "Using SSH Password to log on to Virtual Server Instance"
    sudo apt-get update && sudo apt-get install sshpass -y
    SSH_CMD="sshpass -p $HOST_PASSWORD"
    SSH_ARG="-o UserKnownHostsFile=/dev/null"
elif [[ -n "$HOST_SSH_KEYS" ]]; then
    echo "Using SSH Key to log on to Virtual Server Instance"
    echo $HOST_SSH_KEYS | base64 -d >vsi.key
    chmod 400 vsi.key
    SSH_ARG="-i vsi.key"
else
    echo "Please provide either SSH Password or SSH Key provided to log on to Virtual Server Instance."
    exit 1
fi

BUILDDIR=/home/${HOST_USER_NAME}/${PIPELINERUNID}
DEPLOY_SCRIPT_PATH="./scripts-repo/${subpath}/deploy.sh"
echo "Creating Build Directory [$BUILDDIR]"
$SSH_CMD ssh $SSH_ARG -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE "mkdir -p ${BUILDDIR}"

echo "Copying the artifacts to the host machine."
$SSH_CMD scp $SSH_ARG -o StrictHostKeyChecking=no ${OBJECTNAME} $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE:${BUILDDIR}
$SSH_CMD scp $SSH_ARG -o StrictHostKeyChecking=no ${DEPLOY_SCRIPT_PATH} $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE:${BUILDDIR}

echo "Extract the new artifacts in the host machine."
$SSH_CMD ssh $SSH_ARG -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR " pwd ; cd ${BUILDDIR} ; tar -xf ${OBJECTNAME} ; rm ${OBJECTNAME} "

echo "Creating the symlink to the build directory.."
curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/backup.sh" --output backup.sh
$SSH_CMD ssh $SSH_ARG -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env PIPELINERUNID=$PIPELINERUNID WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR HOST_USER_NAME=$HOST_USER_NAME 'bash -s' < ./backup.sh

echo "Login to the VSI Instance and process the deployment."
$SSH_CMD ssh $SSH_ARG -o StrictHostKeyChecking=no \
    $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR HOST_USER_NAME=$HOST_USER_NAME "bash /$WORKDIR/deploy.sh"
