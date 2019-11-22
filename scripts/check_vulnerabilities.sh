#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_vulnerabilities.sh) and 'source' it from your pipeline job
#    source ./scripts/check_vulnerabilities.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_vulnerabilities.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_vulnerabilities.sh

# Check for vulnerabilities of built image using Vulnerability Advisor

# Input env variables (can be received via a pipeline environment properties.file.
# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties | grep -v -i password
else 
  echo "build.properties : not found"
fi 

# If running after build_image.sh in same stage, reuse the exported variable PIPELINE_IMAGE_URL
if [ -z "${PIPELINE_IMAGE_URL}" ]; then
  PIPELINE_IMAGE_URL=${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}
else
  # extract from img url
  REGISTRY_URL=$(echo ${PIPELINE_IMAGE_URL} | cut -f1 -d/)
  REGISTRY_NAMESPACE=$(echo ${PIPELINE_IMAGE_URL} | cut -f2 -d/)
  IMAGE_NAME=$(echo ${PIPELINE_IMAGE_URL} | cut -f3 -d/ | cut -f1 -d:)
  IMAGE_TAG=$(echo ${PIPELINE_IMAGE_URL} | cut -f3 -d/ | cut -f2 -d:)
fi
echo "PIPELINE_IMAGE_URL=${PIPELINE_IMAGE_URL}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"

# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://cloud.ibm.com/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

echo -e "Details for image: ${PIPELINE_IMAGE_URL}"
ibmcloud cr image-inspect ${PIPELINE_IMAGE_URL}

echo -e "Checking vulnerabilities in image: ${PIPELINE_IMAGE_URL}"
for ITER in {1..30}
do
  set +e
  VA_OUPUT=$(ibmcloud cr va -e -o json ${PIPELINE_IMAGE_URL})
  # ibmcloud cr va returns a non valid json output if image not yet scanned
  if echo $VA_OUPUT | jq -r '.'; then
    STATUS=$( echo $VA_OUPUT | jq -r '.[0].status' )
  else
    echo "$VA_OUPUT"
    STATUS="UNSCANNED"
  fi
  set -e
  # Possible status from Vulnerability Advisor: OK, UNSUPPORTED, INCOMPLETE, UNSCANNED, FAIL, WARN
  if [[ ${STATUS} != "INCOMPLETE" && ${STATUS} != "UNSCANNED" ]]; then
    break
  fi
  echo -e "${ITER} STATUS ${STATUS} : A vulnerability report was not found for the specified image."
  echo "Either the image doesn't exist or the scan hasn't completed yet. "
  echo "Waiting for scan to complete..."
  sleep 10
done
set +e
ibmcloud cr va -e ${PIPELINE_IMAGE_URL}
set -e
ibmcloud cr va -e -o json ${PIPELINE_IMAGE_URL} > "va_status_$IMAGE_NAME.json"
# Record vulnerability information
if jq -e '.services[] | select(.service_id=="draservicebroker")' _toolchain.json > /dev/null 2>&1; then
  ibmcloud doi publishtestrecord --logicalappname="${APP_NAME:-$IMAGE_NAME}" --buildnumber=$SOURCE_BUILD_NUMBER --filelocation "./va_status_$IMAGE_NAME.json" --type vulnerabilityadvisor
fi
STATUS=$( cat "va_status_$IMAGE_NAME.json" | jq -r '.[0].status' )
[[ ${STATUS} == "OK" ]] || [[ ${STATUS} == "UNSUPPORTED" ]] || [[ ${STATUS} == "WARN" ]] || { echo "ERROR: The vulnerability scan was not successful, check the OUTPUT of the command and try again."; exit 1; }