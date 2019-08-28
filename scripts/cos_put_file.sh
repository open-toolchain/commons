#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/cos_put_file.sh) and 'source' it from your pipeline job
#    source ./scripts/cos_put_file.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cos_put_file.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cos_put_file.sh

# This script uploads a given file into a COS bucket

# Input env variables (can be received via a pipeline environment properties.file.
echo "COS_SERVICE_INSTANCE=${COS_SERVICE_INSTANCE}"
echo "COS_BUCKET=${COS_BUCKET}"
echo "FILE_LOCATION=${FILE_LOCATION}"
echo "FILE_CONTENT_TYPE=${FILE_CONTENT_TYPE}"

ibmcloud login --apikey ${IBM_CLOUD_API_KEY} --no-region
if ! ibmcloud plugin list | grep cloud-object-storage ; then ibmcloud plugin install cloud-object-storage ; fi

# Store file in bucket
ibmcloud cos config list
ibmcloud target -g '' # find service instance across all groups
COS_SERVICE_INSTANCE_CRN=$(ibmcloud resource service-instance ${COS_SERVICE_INSTANCE} --output json | jq -r '.[0].id')
ibmcloud cos config crn --crn ${COS_SERVICE_INSTANCE_CRN} --force
COS_BUCKET_REGION=$( ibmcloud cos get-bucket-location --bucket ${COS_BUCKET} | grep Region: | awk '{print $2}' )
ibmcloud cos config region --region ${COS_BUCKET_REGION} # bucket location required to later create more keys
ibmcloud cos config list

# List all files in bucket
ibmcloud cos put-object \
  --bucket ${COS_BUCKET} --key ${FILE_LOCATION} \
  --body ./${FILE_LOCATION} --content-type ${FILE_CONTENT_TYPE}

ibmcloud cos list-objects --bucket ${COS_BUCKET}