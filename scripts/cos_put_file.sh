#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/cos_put_file.sh) and 'source' it from your pipeline job
#    source ./scripts/cos_put_file.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cos_put_file.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cos_put_file.sh

# This script stores a given file into a COS bucket

cos_config() {
  local cos_service_instance=$1
  local cos_bucket=$2
  
  if ! ibmcloud plugin list | grep cloud-object-storage ; then ibmcloud plugin install cloud-object-storage ; fi

  # Set cos service config
  ibmcloud cos config list
  ibmcloud target -g '' # find service instance across all groups
  local cos_service_crn=$(ibmcloud resource service-instance ${cos_service_instance} --output json | jq -r '.[0].id')
  ibmcloud cos config crn --crn ${cos_service_crn} --force
  local cos_bucket_region=$( ibmcloud cos get-bucket-location --bucket ${cos_bucket} | grep Region: | awk '{print $2}' )
  ibmcloud cos config region --region ${cos_bucket_region} # bucket location required to later create more keys
  ibmcloud cos config ddl --ddl $(pwd) # set download location to current directory
  ibmcloud cos config list
}

cos_get_file() {
  local cos_service_instance=$1
  local cos_bucket=$2
  local file_location=$3

  echo "cos_service_instance=${cos_service_instance}"
  echo "cos_bucket=${cos_bucket}"
  echo "file_location=${file_location}"
  
  # Set cos service config
  cos_config ${cos_service_instance} ${cos_bucket}

  # Store file in bucket
  ibmcloud cos get-object \
    --bucket ${cos_bucket} --key ${file_location}

  # List fetched file
  ls -al ${file_location}
}

cos_put_file() {
  local cos_service_instance=$1
  local cos_bucket=$2
  local file_location=$3

  echo "cos_service_instance=${cos_service_instance}"
  echo "cos_bucket=${cos_bucket}"
  echo "file_location=${file_location}"
  
  # Set cos service config
  cos_config ${cos_service_instance} ${cos_bucket}

  # Store file in bucket
  file_content_type=$( file -b --mime-type ${file_location} )
  ibmcloud cos put-object \
    --bucket ${cos_bucket} --key ${file_location} \
    --body ./${file_location} --content-type ${file_content_type}

  # List all files in bucket
  ibmcloud cos list-objects --bucket ${cos_bucket}
}