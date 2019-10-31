#!/bin/bash
# uncomment to debug the script
# set -x
if [ -z "$REGISTRY_URL" ]; then
  # Use the ibmcloud cr info to find the target registry url 
  export REGISTRY_URL=$(ibmcloud cr info | grep -m1 -i '^Container Registry' | awk '{print $3;}')
fi

export GUN="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
export DOCKER_CONTENT_TRUST_SERVER=${DOCKER_CONTENT_TRUST_SERVER:-"https://$REGISTRY_URL:4443"}
echo "DOCKER_CONTENT_TRUST_SERVER=$DOCKER_CONTENT_TRUST_SERVER"


#remove the key from json
function findSigner {
    local SIGNER=$1
    local IMAGE_TAG=$2
    local GUN=$3
    trustData=$(docker trust inspect "$GUN")
    # Check if the Builder signature is present
    if jq -e ".[] | .SignedTags[] | select(.SignedTag=\"$IMAGE_TAG\") | select (.Signers[] | contains(\"$SIGNER\"))" <<<"$trustData"; then
        echo "$BUILD_SIGNER found"
        echo "true"
    else
        echo "$BUILD_SIGNER not found"
        echo "false"
    fi
}

function findTrustData {
    local GUN=$1
    trustData=$(docker trust inspect "$GUN")
    result=$(jq -e ".[]" <<<"$trustData")
    if [ "$result" ]; then
        echo "true"
    else
        echo "false"
    fi
}
