#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_publish_gate_component_helm_chart.sh) and 'source' it from your pipeline job
#    source ./scripts/check_publish_gate_component_helm_chart.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_publish_gate_component_helm_chart.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_publish_gate_component_helm_chart.sh

# Checks a component quality gate
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "APP_NAME=${APP_NAME}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "SOURCE_BUILD_NUMBER=${SOURCE_BUILD_NUMBER}"
echo "POLICY_NAME: ${POLICY_NAME}"
echo "IBM_CLOUD_API_KEY: ${IBM_CLOUD_API_KEY}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties | grep -v -i password
else 
  echo "build.properties : not found"
fi 

# List files available
ls -l 

echo "Note: this script has been updated to use ibmcloud doi plugin - iDRA being deprecated"
echo "iDRA based version of this script is located at: https://github.com/open-toolchain/commons/blob/v1.0.idra_based/scripts/check_publish_gate_component_helm_chart.sh"

# Evaluate the gate against the version matching the git commit
ibmcloud login --apikey $IBM_CLOUD_API_KEY --no-region
ibmcloud doi evaluategate --logicalappname="${APP_NAME}" --buildnumber=${SOURCE_BUILD_NUMBER} --policy="${POLICY_NAME}" --forcedecision=true

# get the process exit code
RESULT=$?  
if [[ ${RESULT} != 0 ]]; then
    exit ${RESULT}
fi
