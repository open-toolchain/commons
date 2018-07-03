#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/publish_umbrella_test_results.sh.sh) and 'source' it from your pipeline job
#    source ./scripts/publish_umbrella_test_results.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_umbrella_test_results.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_umbrella_test_results.sh

# This script does upload current test results for all components in an given umbrella chart which would be updated from respective CI pipelines (see also https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh)
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "PIPELINE_STAGE_INPUT_REV=${PIPELINE_STAGE_INPUT_REV}"
echo "CHART_PATH=${CHART_PATH}"
echo "FILE_LOCATION=${FILE_LOCATION}"
echo "TEST_TYPE=${TEST_TYPE}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
else 
  echo "build.properties : not found"
fi 
# copy latest version of each component insights config
if [[ ! -d ./insights ]]; then
  echo "Cannot find Insights config information in /insights folder"
  exit 1
fi

# Install DRA CLI
export PATH=/opt/IBM/node-v4.2/bin:$PATH
npm install -g grunt-idra3

ls ./insights/*
for INSIGHT_CONFIG in $( ls -v ${CHART_PATH}/insights); do

  echo -e "Publish results for component: ${INSIGHT_CONFIG}"
  export LOGICAL_APP_NAME=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep LOGICAL_APP_NAME | cut -d'=' -f2 )
  export BUILD_PREFIX=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep BUILD_PREFIX | cut -d'=' -f2 )
  export PIPELINE_STAGE_INPUT_REV=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep PIPELINE_STAGE_INPUT_REV | cut -d'=' -f2 )
  echo -e "LOGICAL_APP_NAME: ${LOGICAL_APP_NAME}"
  echo -e "BUILD_PREFIX: ${BUILD_PREFIX}"
  echo -e "PIPELINE_STAGE_INPUT_REV: ${PIPELINE_STAGE_INPUT_REV}"
  # publish the results for all components
  idra --publishtestresult --filelocation=${FILE_LOCATION} --type=${TEST_TYPE}

  # get the process exit code
  RESULT=$?  
  if [[ ${RESULT} != 0 ]]; then
      exit ${RESULT}
  fi
done