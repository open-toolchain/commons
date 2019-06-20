#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/build_umbrella_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/check_umbrella_gate.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh

# This script does test quality gates for all components in an umbrella chart which would be updated from respective CI pipelines (see also https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_umbrella_gate.sh)
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "CHART_PATH=${CHART_PATH}"
echo "IBM_CLOUD_API_KEY=${IBM_CLOUD_API_KEY}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties | grep -v -i password
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

ibmcloud login --apikey $IBM_CLOUD_API_KEY --no-region

ls ./insights/*
for INSIGHT_CONFIG in $( ls -v ${CHART_PATH}/insights); do
  echo -e "Checking gate for component: ${INSIGHT_CONFIG}"

  APP_NAME=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep APP_NAME | cut -d'=' -f2 )
  GIT_BRANCH=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep GIT_BRANCH | cut -d'=' -f2 )
  SOURCE_BUILD_NUMBER=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep SOURCE_BUILD_NUMBER | cut -d'=' -f2 )
  POLICY_NAME=$( printf "${POLICY_NAME_FORMAT}" ${APP_NAME} ${LOGICAL_ENV_NAME} )
  
  echo -e "APP_NAME: ${APP_NAME}"
  echo -e "SOURCE_BUILD_NUMBER: ${SOURCE_BUILD_NUMBER}"
  echo -e "POLICY_NAME: ${POLICY_NAME}"

  # If DOI_BUILD_PREFIX exists in the devops-insights properties file, the script is used in the context
  # of toolchain created from a template using iDRA.
  DOI_BUILD_PREFIX=$( cat ${CHART_PATH}/insights/${INSIGHT_CONFIG} | grep DOI_BUILD_PREFIX | cut -d'=' -f2 )
  if [ -z "$DOI_BUILD_PREFIX" ]; then
    DOI_BUILD_NUMBER=${SOURCE_BUILD_NUMBER}
  else
    DOI_BUILD_NUMBER="${DOI_BUILD_PREFIX}:${SOURCE_BUILD_NUMBER}"
  fi

  # Evaluate the gate against the version matching the git commit
  ibmcloud doi evaluategate --logicalappname="${APP_NAME}" --buildnumber=${DOI_BUILD_NUMBER} --policy="${POLICY_NAME}" --forcedecision=true
  # get the process exit code
  RESULT=$?  
  if [[ ${RESULT} != 0 ]]; then
      exit ${RESULT}
  fi
done
