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

echo "Build environment variables:"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "CHART_PATH=${CHART_PATH}"
echo "POLICY_NAME=${POLICY_NAME}"

# copy latest version of each component insights config
if [[ ! -d ./insights ]]; then
  echo "Cannot find Insights config information in /insights folder"
  exit 1
fi

ls ./insights/*
for INSIGHT_CONFIG in $( ls -v ${CHART_PATH}/insights); do
  echo -e "Checking gate for component: ${INSIGHT_CONFIG}"
  source ${INSIGHT_CONFIG}
  echo -e "LOGICAL_APP_NAME: ${LOGICAL_APP_NAME}"
  echo -e "BUILD_PREFIX: ${BUILD_PREFIX}"
  echo -e "BUILD_ID: ${BUILD_ID}"
  # get the decision
  idra --evaluategate  --policy=${POLICY_NAME} --forcedecision=true
  # get the process exit code
  RESULT=$?  
  if [[ ${RESULT} != 0 ]]; then
      exit ${RESULT}
  fi
done

exit 0
