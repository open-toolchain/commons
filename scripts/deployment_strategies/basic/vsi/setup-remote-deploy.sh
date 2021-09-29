#!/bin/bash
set -e -o pipefail

# This step logs into the Virtual Server Instance based on the credentials provided during the Toolchain creation.
# The step:
#   - Assumes that the upstream task has already downloaded the artifact to the /output location
#   - Carries out all the operation within the home directory of the user i.e. /home/${HOST_USER_NAME}
#   - Copies the artifact from the /output to /home/${HOST_USER_NAME}/app which is defined as WORKDIR
#   - Runs the deploy.sh file as created in the previous step to carry out the step-by-step deployment which may include start/stop of application.

#source the utility functions
source <(curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/utility.sh")
VsiCommand=$(checkVSICredentials "$HOST_USER_NAME" "$HOST_SSH_KEYS")
if [ $? -eq 1 ]; then
    echo $VsiCommand
    exit 1
fi

BUILDDIR=/home/${HOST_USER_NAME}/${PIPELINERUNID}
DEPLOY_SCRIPT_PATH="./scripts-repo/${subpath}/deploy.sh"
HEALTH_SCRIPT_PATH="./scripts-repo/${subpath}/health-check.sh"
echo "Creating Build Directory [$BUILDDIR]"
ssh $VsiCommand -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE "mkdir -p ${BUILDDIR}"

echo "Copying the artifacts to the host machine."
scp $VsiCommand -o StrictHostKeyChecking=no ${OBJECTNAME} $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE:${BUILDDIR}
scp $VsiCommand -o StrictHostKeyChecking=no ${DEPLOY_SCRIPT_PATH} $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE:${BUILDDIR}
scp $VsiCommand -o ProxyCommand="$ProxyCommand" ${HEALTH_SCRIPT_PATH} $BASTION_HOST_USER_NAME@$Pool_Member_IP:${BUILDDIR}

echo "Extract the new artifacts in the host machine."
ssh $VsiCommand -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR " pwd ; cd ${BUILDDIR} ; tar -xf ${OBJECTNAME} ; rm ${OBJECTNAME} "

echo "Creating the symlink to the build directory.."
curl -sSL "$COMMON_HOSTED_REGION/scripts/deployment_strategies/basic/vsi/backup.sh" --output backup.sh
ssh $VsiCommand -o StrictHostKeyChecking=no $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env PIPELINERUNID=$PIPELINERUNID WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR HOST_USER_NAME=$HOST_USER_NAME 'bash -s' <./backup.sh

echo "Login to the VSI Instance and process the deployment."
ssh $VsiCommand -o StrictHostKeyChecking=no \
    $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env USERID=$USERID TOKEN=$TOKEN REPO=$REPO APPNAME=$APPNAME COSENDPOINT=$COSENDPOINT COSBUCKETNAME=$COSBUCKETNAME OBJECTNAME=$OBJECTNAME WORKDIR=$WORKDIR BUILDDIR=$BUILDDIR HOST_USER_NAME=$HOST_USER_NAME "bash /$WORKDIR/deploy.sh"

# Do the health check
sleep 10
if ssh $VsiCommand $HOST_USER_NAME@$VIRTUAL_SERVER_INSTANCE env VIRTUAL_SERVER_INSTANCE=$VIRTUAL_SERVER_INSTANCE "$WORKDIR/health-check.sh" ; then
    echo "Health Check passed."
else
    exit 1
fi
