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
echo "BUILD_PREFIX=${BUILD_PREFIX}"
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

# Ensure comptability with iDRA previous usage in the templates
if [ -z "$LOGICAL_APP_NAME"]; then
  export DOI_BUILD_NUMBER=${SOURCE_BUILD_NUMBER}
else 
  # the script is used in a toolchain created with a template that was using iDRA tool
  # ensure compatibility with ibmcloud doi plugin
  export DOI_NO_AUTO=true
  export APP_NAME=${LOGICAL_APP_NAME}
  export DOI_BUILD_NUMBER="${BUILD_PREFIX}:${SOURCE_BUILD_NUMBER}"
fi

# List files available
ls -l 

# Evaluate the gate against the version matching the git commit
ibmcloud login --apikey $IBM_CLOUD_API_KEY --no-region
ibmcloud doi evaluategate --logicalappname="${APP_NAME}" --buildnumber=${DOI_BUILD_NUMBER} --policy="${POLICY_NAME}" --forcedecision=true

# get the process exit code
RESULT=$?  
if [[ ${RESULT} != 0 ]]; then
    exit ${RESULT}
fi
