#!/bin/bash

#################################
## This script can be executed in a Source repo which contains only K8's deployment manifest files.
## It will create a IBM satellite configuration along with version.
## It will apply subscription to a satellite cluster group.
#################################

RED="\e[31m"
GREEN="\e[32m"
ENDCOLOR="\e[0m"

function printLog() {
  echo -e "\n${GREEN}$1${ENDCOLOR} \n"
}

function printWarning() {
  echo -e "\n${RED}$1${ENDCOLOR} \n"
}


function getAPPUrlSatConfig() {
  for filename in $(find /artifacts/${MANIFEST_DIR} -type f -print); do   
    printLog "Creating Satellite Config for resources present in source file ${filename}."
    route_name=$(yq -o=json eval ${filename} |   jq -r  'select(.kind=="Route") | .metadata.name')  
     if [ ! -z "${route_name}" ]; then
      if grep -q "razee/watch-resource: lite" ${filename}; then
        break;
      else 
       printWarning  "\n\nDid not find [razee/watch-resource: lite] label in your deployment file.  Unable to fetch the host url. Please visit https://cloud.ibm.com/docs/satellite?topic=satellite-satcon-manage&mhsrc=ibmsearch_a&mhq=razee%2Fwatch-resource%3A+lite#satconfig-enable-watchkeeper-specific \n\n"
       return
      fi
    fi
  done

  if [ -z "${route_name}" ]; then
    printWarning "\n\n Unable to find OpenShift Route resource type in the ${MANIFEST_DIR} directory......\n\n"
    return
  fi

  for ITER in {1..30}
    do
        resources_ids=$(ic sat resource ls -output json |  jq -r ".resources.resources[] | select(.searchableData.name==\"$route_name\") | select(.searchableData.namespace==\"$CLUSTER_NAMESPACE\") | .id ")
        resource_id=$(echo "${resources_ids}" | awk '{print $1}' |  head -n 1)
        if [ -z "${resource_id}" ]
        then
          printLog "Waiting for application deployment to be on completed....${ITER}"
        else
          APPURL=$(ibmcloud sat resource get --resource  "${resource_id}" --output json | jq -r '.resource.data' | jq -r '.status.ingress[0].host')
        fi
      if [ -z  "${APPURL}"  ] || [[  "${APPURL}" = "null"  ]]; then 
        printLog "Waiting for Host URL, Sleping for 20 seconds ...."
        sleep 20
      else
        break
      fi
    done
}

function createAndDeploySatelliteConfig() {

printLog "=========================================================="
APP_NAME=$1
SAT_CONFIG=$2
SAT_CONFIG_VERSION=$3
DEPLOY_FILE=$4
printLog "Creating config for ${SAT_CONFIG}...."

export SATELLITE_SUBSCRIPTION="${APP_NAME}-${SAT_CONFIG}"
export SAT_CONFIG_VERSION
if ! ic sat config version get --config "${APP_NAME}" --version "${SAT_CONFIG_VERSION}" &>/dev/null; then
  printLog "Satellite Config resource with version  ${SAT_CONFIG_VERSION} not found, creating it now."
  if ! ibmcloud sat config get --config "${APP_NAME}" &>/dev/null ; then
    ibmcloud sat config create --name "${APP_NAME}"
  fi
  printLog "Creating Satellite Config resource from source file ${DEPLOY_FILE}"
  ibmcloud sat config version create --name "${SAT_CONFIG_VERSION}" --config "${APP_NAME}" --file-format yaml --read-config "${DEPLOY_FILE}"
else
  printLog "Satellite Config resource with version ${SAT_CONFIG_VERSION} already found."
fi

EXISTING_SUB=$(ibmcloud sat subscription ls -q | grep "${SATELLITE_SUBSCRIPTION}" || true)
  if [ -z "${EXISTING_SUB}" ]; then
    printLog "Satellite subscription with subscription name ${SATELLITE_SUBSCRIPTION} not found. Creating it now."
    ibmcloud sat subscription create --name "${SATELLITE_SUBSCRIPTION}" --group "${SATELLITE_CLUSTER_GROUP}" --version "${SAT_CONFIG_VERSION}" --config "${APP_NAME}"
  else
    printLog "Satellite subscription with subscription name ${SATELLITE_SUBSCRIPTION} already found. Updating it now."
    ibmcloud sat subscription update --subscription "${SATELLITE_SUBSCRIPTION}" -f --group "${SATELLITE_CLUSTER_GROUP}" --version "${SAT_CONFIG_VERSION}"
fi
}

ls -laht /artifacts/${MANIFEST_DIR}
commit=$(git log -1 --pretty=format:%h)
for filename in $(find /artifacts/${MANIFEST_DIR} -type f -print); do   
  printLog "Searching for OpenShift Route resource type in file ${filename}" 
  config_name=$(basename ${filename} | cut -d. -f1)
  config_name_version=${config_name}_${commit} 
  createAndDeploySatelliteConfig ${APP_NAME} ${config_name} ${config_name_version} ${filename}
done

getAPPUrlSatConfig

SATELLITE_CONFIG_ID=$( ibmcloud sat config get --config "${APP_NAME}" --output json | jq -r .uuid )
printLog "Please check details at https://cloud.ibm.com/satellite/configuration/${SATELLITE_CONFIG_ID}/overview"

if [ -z  "${APPURL}"  ] || [[  "${APPURL}" = "null"  ]]; then 
  printWarning "Unable to get Host URL....."
else
  printLog "Route to the host is  ${APPURL}"
fi



