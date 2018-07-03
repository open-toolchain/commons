#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/build_umbrella_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/check_umbrella_gate.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh

# This script does test quality gates for all components in an umbrella chart which would be updated from respective CI pipelines (see also https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh)
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "CHART_PATH=${CHART_PATH}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
else 
  echo "build.properties : not found"
fi 

# List files available
ls -l 

# Copy latest version of each component insights config
if [[ ! -d ./insights ]]; then
  echo "Cannot find Insights config information in /insights folder"
  exit 1
fi

# Install DRA CLI
export PATH=/opt/IBM/node-v4.2/bin:$PATH
npm install -g grunt-idra3

ls ./insights/*
for INSIGHT_CONFIG in $( ls -v ${CHART_PATH}/insights); do
  echo -e "Checking gate for component: ${INSIGHT_CONFIG}"

  export LOGICAL_APP_NAME=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep LOGICAL_APP_NAME | cut -d'=' -f2 )
  export BUILD_PREFIX=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep BUILD_PREFIX | cut -d'=' -f2 )
  export PIPELINE_STAGE_INPUT_REV=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep PIPELINE_STAGE_INPUT_REV | cut -d'=' -f2 )
  POLICY_NAME=$( printf "${POLICY_NAME_FORMAT}" ${LOGICAL_APP_NAME} ${LOGICAL_ENV_NAME} )
  
  echo -e "LOGICAL_APP_NAME: ${LOGICAL_APP_NAME}"
  echo -e "BUILD_PREFIX: ${BUILD_PREFIX}"
  echo -e "PIPELINE_STAGE_INPUT_REV: ${PIPELINE_STAGE_INPUT_REV}"
  echo -e "POLICY_NAME: ${POLICY_NAME}"

  # get the decision
  idra --evaluategate --policy="${POLICY_NAME}" --forcedecision=true
  # get the process exit code
  RESULT=$?  
  if [[ ${RESULT} != 0 ]]; then
      exit ${RESULT}
  fi
done
