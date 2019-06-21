#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/publish_umbrella_test_results.sh.sh) and 'source' it from your pipeline job
#    source ./scripts/publish_umbrella_test_results.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_umbrella_test_results.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_umbrella_test_results.sh

# This script does upload current test results for all components in an given umbrella chart which would be updated from respective CI pipelines (see also https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh)
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "CHART_PATH=${CHART_PATH}"
echo "FILE_LOCATION=${FILE_LOCATION}"
echo "TEST_TYPE=${TEST_TYPE}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties | grep -v -i password
else 
  echo "build.properties : not found"
fi 
# copy latest version of each component insights config
if [[ ! -d ./insights ]]; then
  echo "Cannot find Insights config information in /insights folder"
  exit 1
fi

ibmcloud login --apikey $IBM_CLOUD_API_KEY --no-region
ls ./insights/*
for INSIGHT_CONFIG in $( ls -v ${CHART_PATH}/insights); do

  echo -e "Publish results for component: ${INSIGHT_CONFIG}"
  APP_NAME=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep APP_NAME | cut -d'=' -f2 )
  GIT_BRANCH=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep GIT_BRANCH | cut -d'=' -f2 )
  SOURCE_BUILD_NUMBER=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep SOURCE_BUILD_NUMBER | cut -d'=' -f2 )
 
  echo -e "APP_NAME: ${APP_NAME}"
  echo -e "GIT_BRANCH: ${GIT_BRANCH}"
  echo -e "SOURCE_BUILD_NUMBER: ${SOURCE_BUILD_NUMBER}"
  # publish the results for each component
  ibmcloud doi publishtestrecord --logicalappname="$APP_NAME" --buildnumber=$SOURCE_BUILD_NUMBER --filelocation=${FILE_LOCATION} --type=${TEST_TYPE}

  # get the process exit code
  RESULT=$?  
  if [[ ${RESULT} != 0 ]]; then
      exit ${RESULT}
  fi
done