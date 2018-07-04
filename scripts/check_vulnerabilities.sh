#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_vulnerabilities.sh) and 'source' it from your pipeline job
#    source ./scripts/check_vulnerabilities.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_vulnerabilities.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_vulnerabilities.sh
# Input env variables (can be received via a pipeline environment properties.file.

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
else 
  echo "build.properties : not found"
fi 

# If running after build_image.sh in same stage, reuse the exported variable PIPELINE_IMAGE_URL
if [[ -z PIPELINE_IMAGE_URL ]]; then
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
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

bx cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}
echo -e "Checking vulnerabilities in image: ${PIPELINE_IMAGE_URL}"
for ITER in {1..30}
do
  set +e
  STATUS=$( bx cr va -e -o json ${PIPELINE_IMAGE_URL} | jq -r '.[0].status' )
  set -e
  if [[ ${STATUS} == "OK" || ${STATUS} == "FAIL" ]]; then
    break
  fi
  echo -e "${ITER} STATUS ${STATUS} : A vulnerability report was not found for the specified image."
  echo "Either the image doesn't exist or the scan hasn't completed yet. "
  echo "Waiting for scan to complete.."
  sleep 10
done
set +e
bx cr va -e ${PIPELINE_IMAGE_URL}
set -e
[[ $(bx cr va -e -o json ${PIPELINE_IMAGE_URL} | jq -r '.[0].status') == "OK" ]] || { echo "ERROR: The vulnerability scan was not successful, check the OUTPUT of the command and try again."; exit 1; }