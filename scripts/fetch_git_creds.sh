#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/build_image.sh) and 'source' it from your pipeline job
#    source ./scripts/fetch_git_creds.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/fetch_git_creds.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/fetch_git_creds.sh

# This script does perform an entire fetch of associated git repo, and copies it into archive_dir output
# along with git credentials stored in build.properties, so as a consuming job could leverage these to repost
# to same or another git repo.

echo "Build environment variables:"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"

#env
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

#echo "Checking archive dir presence"
cp -R -n ./ $ARCHIVE_DIR/ || true

# Record git info to later contribute to umbrella chart repo
GIT_REMOTE_URL=$( git config --get remote.origin.url )
GIT_USER=$( echo ${GIT_REMOTE_URL} | cut -d/ -f3 | cut -d: -f1 )
GIT_PASSWORD=$( echo ${GIT_REMOTE_URL} | cut -d: -f3 | cut -d@ -f1 )

mkdir -p $ARCHIVE_DIR
echo "SOURCE_GIT_URL=${GIT_URL}" >> $ARCHIVE_DIR/build.properties
echo "SOURCE_GIT_COMMIT=${GIT_COMMIT}" >> $ARCHIVE_DIR/build.properties
echo "SOURCE_GIT_USER=${GIT_USER}" >> $ARCHIVE_DIR/build.properties
echo "SOURCE_GIT_PASSWORD=${GIT_PASSWORD}" >> $ARCHIVE_DIR/build.properties

cat $ARCHIVE_DIR/build.properties