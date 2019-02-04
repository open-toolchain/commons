#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/record_deployment.sh) and 'source' it from your pipeline job
#    source ./scripts/record_deployment.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/record_deployment.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/record_deployment.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "GIT_URL=${GIT_URL}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "GIT_COMMIT=${GIT_COMMIT}"
echo "TIMESTAMP=${TIMESTAMP}"
echo "TARGET_REGION_ID=${TARGET_REGION_ID}"
echo "TARGET_REGION_NAME=${TARGET_REGION_NAME}"
echo "TARGET_ORG_NAME=${TARGET_ORG_NAME}"
echo "TIMESTAMP=${TIMESTAMP}"

# View build properties
if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
else 
  echo "build.properties : not found"
fi
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://cloud.ibm.com/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

echo "=========================================================="
echo "FETCHING UMBRELLA repo"
echo -e "Locating target umbrella repo: ${UMBRELLA_REPO_NAME}"
if [ -z ${TOOLCHAIN_JSON} ]; then
  echo "### TODO remove this once TOOLCHAIN_JSON publicly available"
  TOOLCHAIN_JSON=$( curl -H "Authorization: ${TOOLCHAIN_TOKEN}" https://otc-api.ng.bluemix.net/api/v1/toolchains/${PIPELINE_TOOLCHAIN_ID}/services )
fi
UMBRELLA_REPO_URL=$( echo ${TOOLCHAIN_JSON} | jq -r '.services[] | select (.parameters.repo_name=="'"${UMBRELLA_REPO_NAME}"'") | .parameters.repo_url ' )
UMBRELLA_REPO_URL=${UMBRELLA_REPO_URL%".git"} #remove trailing .git if present
# Augment URL with git user & password
UMBRELLA_ACCESS_REPO_URL=${UMBRELLA_REPO_URL:0:8}${SOURCE_GIT_USER}:${SOURCE_GIT_PASSWORD}@${UMBRELLA_REPO_URL:8}
echo -e "Located umbrella repo: ${UMBRELLA_REPO_URL}, with access token: ${UMBRELLA_ACCESS_REPO_URL}"

curl -X POST \
  https://otc-api.ng.bluemix.net/v1/toolchain_deployable_mappings \
  -H "accept: application/json" \
  -H "Authorization: ${TOOLCHAIN_TOKEN}" \
  -H "cache-control: no-cache" \
  -H "content-type: application/json" \
  -d "{
    'deployable': {
        'organization_guid': '8d34d127-d3db-43cd-808b-134b388f1646',
        'space_guid': '5f9f2e5f-610c-4013-b34c-84c6bf4ccf30',
        'region_id': '${TARGET_REGION_ID}',
        'deployable_guid': '6e3bc311-c83d-4cd1-a457-99d9a5f20f19',
        'type': 'app'
    },
    'toolchain': {
        'toolchain_guid': '${PIPELINE_TOOLCHAIN_ID}',
        'region_id': 'ibm:yp:us-south'
    },
    'source': {
        'source_guid': '${PIPELINE_SERVICE_ID}',
        'type': 'service_instance'
    },
    'experimental': {
        'inputs': [{
            'service_instance_id': '${GIT_REPO_SERVICE_ID}',
            'data': {
                'repo_url': '${SOURCE_GIT_URL}',
                'repo_branch': '${SOURCE_GIT_BRANCH}',
                'timestamp': '${TIMESTAMP}',
                'revision_url': 'https://github.com/jauninb/traceability/commit/259d748f63da825d9576075c7413f432c5aa1e94'
            }
        }],
        'env': {
            'space_name': "",
            'region_name': '${TARGET_REGION_NAME}',
            'region_id': '${TARGET_REGION_ID}',
            'label': '${PIPELINE_CLUSTER_NAME}:${CLUSTER_NAMESPACE}',
            'org_name': '${TARGET_ORG_NAME}'
        }
    }
  }"
  
#   curl -X POST \
#   https://otc-api.ng.bluemix.net/v1/toolchain_deployable_mappings \
#   -H 'accept: application/json' \
#   -H "Authorization: ${TOOLCHAIN_TOKEN}" \
#   -H 'cache-control: no-cache' \
#   -H 'content-type: application/json' \
#   -d '{
#     "deployable": {
#         "organization_guid": "8d34d127-d3db-43cd-808b-134b388f1646",
#         "space_guid": "5f9f2e5f-610c-4013-b34c-84c6bf4ccf30",
#         "region_id": "w3ibm:prod:us-south",
#         "deployable_guid": "6e3bc311-c83d-4cd1-a457-99d9a5f20f19",
#         "type": "app"
#     },
#     "toolchain": {
#         "toolchain_guid": "'${PIPELINE_TOOLCHAIN_ID}'",
#         "region_id": "ibm:yp:us-south"
#     },
#     "source": {
#         "source_guid": "'${PIPELINE_SERVICE_ID}'",
#         "type": "service_instance"
#     },
#     "experimental": {
#         "inputs": [{
#             "service_instance_id": "'${GIT_REPO_SERVICE_ID}'",
#             "data": {
#                 "repo_url": "'${SOURCE_GIT_URL}'",
#                 "repo_branch": "'${SOURCE_GIT_BRANCH}'",
#                 "timestamp": "'${TIMESTAMP}'",
#                 "revision_url": "https://github.com/jauninb/traceability/commit/259d748f63da825d9576075c7413f432c5aa1e94"
#             }
#         }],
#         "env": {
#             "space_name": "",
#             "region_name": "US South",
#             "region_id": "'${TARGET_REGION_ID}'",
#             "label": "'${PIPELINE_CLUSTER_NAME}':'${CLUSTER_NAMESPACE}'",
#             "org_name": "bluemix_ui_load0303t003@mailinator.com"
#         }
#     }
#   }'



# curl -X POST \
#   https://otc-api.ng.bluemix.net/v1/toolchain_deployable_mappings \
#   -H 'accept: application/json' \
#   -H 'authorization: Bearer <bearerToken>' \
#   -H 'cache-control: no-cache' \
#   -H 'content-type: application/json' \
#   -d '{
#   "deployable": {
#     "deployable_guid": "464b31a4-e335-4bfc-95a3-96a18131d2b4",
#     "type": "app",
#     "region_id": "ibm:yp:us-south",
#     "organization_guid": "3f5d4d3c-6ece-4e9c-abcd-42c8fcc199aa"
#   },
#   "toolchain": {
#     "toolchain_guid": "7b6a28be-d7f4-4c11-8f53-e6ed1b9870ec",
#     "region_id": "ibm:ys1:us-south"
#   },
#   "source": {
#     "type": "ui",
#     "source_guid": ""
#   }
# }'




# curl -X POST \
#   https://devops-api.stage1.ng.bluemix.net/v1/toolchain_deployable_mappings \
#   -H 'authorization: Bearer <bearerToken>' \
#   -H 'cache-control: no-cache' \
#   -H 'content-type: application/json' \
#   -H 'postman-token: 9cd6a716-feaa-2c0c-cf0b-4ba51fbab37e' \
#   -d '{
#     "deployable": {
#         "deployable_guid": "4c2831ab-9657-4f2c-afcd-d844e615ae",
#         "organization_guid": "f965f4ed-1fbc-4f3a-8271-bc0a3e07af6d",
#         "region_id": "ibm:ys1:us-south",
#         "type": "container"
#     },
#     "source": {
#         "source_guid": "",
#         "type": "ui"
#     },
#     "toolchain": {
#         "region_id": "ibm:ys1:us-south",
#         "toolchain_guid": "a79814c2-53c5-4a9a-ad7b-65b71e56579d"
#     }
# }'  


# {
#     "deployable": {
#         "organization_guid": "8d34d127-d3db-43cd-808b-134b388f1646",
#         "space_guid": "5f9f2e5f-610c-4013-b34c-84c6bf4ccf30",
#         "region_id": "w3ibm:prod:us-south",
#         "deployable_guid": "6e3bc311-c83d-4cd1-a457-99d9a5f20f19",
#         "type": "app"
#     },
#     "toolchain": {
#         "toolchain_guid": "5b0e83af-8cba-4fdb-b2e4-3cbc7acd1dab",
#         "region_id": "w3ibm:prod:us-south"
#     },
#     "source": {
#         "source_guid": "4bc67eb7-6089-4381-bd01-f920hydb2def",
#         "type": "service_instance"
#     },
#     "experimental": {
#         "inputs": [{
#             "service_instance_id": "9bc87eb7-6089-4381-bd01-e920dcdb2eac",
#             "data": {
#                 "repo_url": "https://github.com/jauninb/traceability.git",
#                 "repo_branch": "master",
#                 "timestamp": 123456798,
#                 "revision_url": "https://github.com/jauninb/traceability/commit/259d748f63da825d9576075c7413f432c5aa1e94"
#             }
#         }],
#         "env": {
#             "space_name": "prod",
#             "region_name": "US South",
#             "region_id": "XXXXXXXXXXXX",
#             "label": "PRODUCTION",
#             "org_name": "bluemix_ui_load0303t003@mailinator.com"
#         }
#     }
# } 
 

 #########################################

#!/bin/bash

# Extract the related GIT var from build.properties
while read -r line ; do
    echo "Processing $line"
    eval "export $line"
done < <(grep GIT build.properties)

# If creating a deployable mapping of type non app, ui is failing/showing internal error
deploymapping_template=$(cat <<'EOT'
{
    "deployable": {
        "deployable_guid": "%s",
        "type": "app",
        "region_id": "%s",
        "organization_guid": "%s"
    },
    "toolchain": {
        "toolchain_guid": "%s",
        "region_id": "%s"
    },
    "source": {
        "type": "service_instance",
        "source_guid": "%s"
    },
    "experimental": {
        "inputs": [{
            "service_instance_id": "%s",
            "data": {
                "repo_url": "%s",
                "repo_branch": "%s",
                "timestamp": "%s",
                "revision_url": "%s"
            }
        }],
        "env": {
            "label": "%s:%s"
        }
    }
}
EOT
)

echo -e "Create the deployable mapping payload"
printf "$deploymapping_template" "$TARGET_DEPLOYABLE_GUID" "$TARGET_REGION_ID" "$PIPELINE_ORGANIZATION_ID" \
  "${PIPELINE_TOOLCHAIN_ID}" "$TARGET_REGION_ID" \
  "${PIPELINE_ID}" \
  "${GIT_REPO_SERVICE_ID}" "${SOURCE_GIT_URL}" "${SOURCE_GIT_BRANCH}" "${SOURCE_GIT_REVISION_TIMESTAMP}" "$SOURCE_GIT_REVISION_URL" \
  "${PIPELINE_KUBERNETES_CLUSTER_NAME}" "${CLUSTER_NAMESPACE}" > deployable_mapping.json

echo -e "Identify the HTTP verb to use"
EXISTING_DEPLOYABLE_MAPPINGS=$(curl -H "Authorization: ${TOOLCHAIN_TOKEN}" "${PIPELINE_API_URL%/pipeline}/toolchain_deployable_mappings?toolchain_guid=${PIPELINE_TOOLCHAIN_ID}")
MAPPING_GUID=$(echo $EXISTING_DEPLOYABLE_MAPPINGS | jq --arg DEPLOYABLE_GUID "$TARGET_DEPLOYABLE_GUID" -r '.items[] | select(.deployable.deployable_guid==$DEPLOYABLE_GUID) | .mapping_guid');

echo "MAPPING_GUID=$MAPPING_GUID"

if [ -z "$MAPPING_GUID" ]; then
   HTTP_VERB="POST"
else 
   HTTP_VERB="PUT"
   COMPLEMENTARY_PATH="/${MAPPING_GUID}"
fi

echo -e "$HTTP_VERB ${PIPELINE_API_URL%/pipeline}/toolchain_deployable_mappings${COMPLEMENTARY_PATH}"
cat deployable_mapping.json

curl -X $HTTP_VERB \
  "${PIPELINE_API_URL%/pipeline}/toolchain_deployable_mappings${COMPLEMENTARY_PATH}" \
  -is \
  -H "Authorization: ${TOOLCHAIN_TOKEN}" \
  -H "cache-control: no-cache" \
  -H "content-type: application/json; charset=utf-8" \
  -d @deployable_mapping.json