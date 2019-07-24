#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/secrets_management.sh) and 'source' it from your pipeline job
#    source ./scripts/secrets_management.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh

## ----------------------------------------------------------------------------
#
# Secrets Management Script Library API:
#
###
# @author: tony.mcguckin@ie.ibm.com
# @copyright: IBM Corporation 2019
###
#
# vault instance management:
#
#   get_vault_instance      :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP
#   delete_vault_instance   :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP
#
###
#
# iam authentication management:
#
#   iam_writer_access       :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SOURCE_SERVICE_NAME $SOURCE_SERVICE_GUID
#
###
#
# secret management:
#
#   save_byok_secret        :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $SECRET_MATERIAL
#   generate_auto_secret    :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $EXTRACTABLE
#   retrieve_secret         :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
#   delete_secret           :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
#
## ----------------------------------------------------------------------------

function save_byok_secret {
    ##
    # save_byok_secret $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $SECRET_MATERIAL
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #save_byok_secret \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_name" \
    #  "LS0tLS1C...my_base64_encoded_secret_material...LQo="

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4
    SECRET_MATERIAL=$5

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME
    check_value $SECRET_MATERIAL

    #section "Begin: save_byok_secret: $VAULT_SERVICE_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    PROCEED=0

    ##
    # create an instance of the secrets management vault if it's not already there...
    ##
    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      #echo "Reusing secrets management vault service named '$VAULT_SERVICE_NAME' as it already exists..."
      PROCEED=1
    else
      #echo "Creating new secrets management vault service instance named '$VAULT_SERVICE_NAME'..."
      ibmcloud resource service-instance-create $VAULT_SERVICE_NAME kms tiered-pricing $VAULT_REGION || exit 1
    fi

    VAULT_MANAGEMENT_URL=https://$VAULT_REGION.kms.cloud.ibm.com/api/v2/keys
    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    ##
    # get or generate a service-key for keyprotect...
    # need this in order to work with iam to get credentials...
    ##
    if check_exists "$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME 2>&1)"; then
      #echo "Reusing secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME' as it already exists..."
      PROCEED=1
    else
      #echo "Creating new secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME'..."
      ibmcloud resource service-key-create $VAULT_SERVICE_SERVICE_KEY_NAME Manager \
        --instance-id "$VAULT_INSTANCE_ID" || exit 1
    fi

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_MANAGEMENT_URL=$VAULT_MANAGEMENT_URL"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "-----------------"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"
    #echo "SECRET_NAME=$SECRET_NAME"
    #echo "SECRET_MATERIAL=$SECRET_MATERIAL"
    #echo "-----------------"

    # get a list of secrets on this vault secrets management instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    #echo "Current list of vault secrets:"
    #echo "$VAULT_SECRETS"
    #echo "-----------------"

    # now check if the we're trying to save a secret that already preexists...
    if echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'")' > /dev/null; then
      #echo "Reusing saved vault BYOK secret named '${SECRET_NAME}' as it already exists..."
      PROCEED=1
    else
      #echo "Creating new vault BYOK secret named '$SECRET_NAME' with specified secret material..."
      NEW_VAULT_SECRET=$(curl -s -X POST $VAULT_MANAGEMENT_URL \
        --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
        --header "Bluemix-Instance: $VAULT_GUID" \
        --header "Prefer: return=minimal" \
        --header "Content-Type: application/vnd.ibm.kms.key+json" \
        -d '{
          "metadata": {
              "collectionType": "application/vnd.ibm.kms.key+json",
              "collectionTotal": 1
          },
          "resources": [
            {
              "name": "'${SECRET_NAME}'",
              "description": "'${SECRET_NAME}'",
              "type": "application/vnd.ibm.kms.key+json",
              "payload": "'${SECRET_MATERIAL}'",
              "extractable": true
            }
          ]
        }')
      check_value $NEW_VAULT_SECRET

      #echo "New vault BYOK secret named '${SECRET_NAME}' creation response from secrets management vault service:"
      #echo "$NEW_VAULT_SECRET"
      #echo "-----------------"

      # retrieve the updated secrets list...
      VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
      --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
      --header "Bluemix-Instance: $VAULT_GUID")
      check_value $VAULT_SECRETS
    fi

    # extract the id of our newly saved (or refetched) secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID
    #echo "New (or refetched) vault BYOK secret named '${SECRET_NAME}' has public facing ID:"
    #echo "$VAULT_SECRET_ID"
    #echo "-----------------"

    #section "End: save_byok_secret: $VAULT_SERVICE_NAME"

    echo $VAULT_SECRET_ID
}

## ----------------------------------------------------------------------------

function generate_auto_secret {
    ##
    # generate_auto_secret $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $EXTRACTABLE
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #generate_auto_secret \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_name" \
    #  false

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4
    EXTRACTABLE=$5

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME
    check_value $EXTRACTABLE

    #section "Begin: generate_auto_secret: $VAULT_SERVICE_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    PROCEED=0

    ##
    # create an instance of the secrets management vault if it's not already there...
    ##
    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      #echo "Reusing secrets management vault service named '$VAULT_SERVICE_NAME' as it already exists..."
      PROCEED=1
    else
      #echo "Creating new secrets management vault service instance named '$VAULT_SERVICE_NAME'..."
      ibmcloud resource service-instance-create $VAULT_SERVICE_NAME kms tiered-pricing $VAULT_REGION || exit 1
    fi

    VAULT_MANAGEMENT_URL=https://$VAULT_REGION.kms.cloud.ibm.com/api/v2/keys
    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    ##
    # get or generate a service-key for keyprotect...
    # need this in order to work with iam to get credentials...
    ##
    if check_exists "$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME 2>&1)"; then
      #echo "Reusing secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME' as it already exists..."
      PROCEED=1
    else
      #echo "Creating new secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME'..."
      ibmcloud resource service-key-create $VAULT_SERVICE_SERVICE_KEY_NAME Manager \
        --instance-id "$VAULT_INSTANCE_ID" || exit 1
    fi

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_MANAGEMENT_URL=$VAULT_MANAGEMENT_URL"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "-----------------"
    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"
    #echo "SECRET_NAME=$SECRET_NAME"
    #echo "EXTRACTABLE=$EXTRACTABLE"
    #echo "-----------------"

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    #echo "Current list of vault secrets:"
    #echo "$VAULT_SECRETS"
    #echo "-----------------"

    # now check if the we're trying to save a key that already preexists...
    if echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'")' > /dev/null; then
      #echo "Reusing saved vault auto secret named '${SECRET_NAME}' as it already exists..."
      PROCEED=1
    else
      #echo "Creating new vault auto secret named '$SECRET_NAME' with specified secret material..."
      NEW_VAULT_SECRET=$(curl -s -X POST $VAULT_MANAGEMENT_URL \
        --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
        --header "Bluemix-Instance: $VAULT_GUID" \
        --header "Prefer: return=minimal" \
        --header "Content-Type: application/vnd.ibm.kms.key+json" \
        -d '{
          "metadata": {
              "collectionType": "application/vnd.ibm.kms.key+json",
              "collectionTotal": 1
          },
          "resources": [
            {
              "name": "'${SECRET_NAME}'",
              "description": "'${SECRET_NAME}'",
              "type": "application/vnd.ibm.kms.key+json",
              "extractable": '${EXTRACTABLE}'
            }
          ]
        }')
      check_value $NEW_VAULT_SECRET

      #echo "New vault auto secret named '${SECRET_NAME}' creation response from secrets management vault service:"
      #echo "$NEW_VAULT_SECRET"
      #echo "-----------------"

      # retrieve the updated secrets list...
      VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
      --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
      --header "Bluemix-Instance: $VAULT_GUID")
      check_value $VAULT_SECRETS
    fi

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID
    #echo "New (or refetched) vault auto secret named '${SECRET_NAME}' has public facing ID:"
    #echo "$VAULT_SECRET_ID"
    #echo "-----------------"

    #section "End: generate_auto_secret: $VAULT_SERVICE_NAME"

    echo $VAULT_SECRET_ID
}

## ----------------------------------------------------------------------------

function retrieve_secret {
    ##
    # retrieve_secret $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #retrieve_secret \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_name"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME

    #section "Begin: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    VAULT_MANAGEMENT_URL=https://$VAULT_REGION.kms.cloud.ibm.com/api/v2/keys
    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_MANAGEMENT_URL=$VAULT_MANAGEMENT_URL"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "-----------------"
    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"
    #echo "SECRET_NAME=$SECRET_NAME"
    #echo "-----------------"

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    #echo "Current list of vault secrets:"
    #echo "$VAULT_SECRETS"
    #echo "-----------------"

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has public facing ID:"
    #echo "$VAULT_SECRET_ID"
    #echo "-----------------"

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has Base64 Key Material:"
    #echo "$RETRIEVED_SECRET_MATERIAL"
    #echo "-----------------"

    #section "End: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    echo $RETRIEVED_SECRET_MATERIAL
}

## ----------------------------------------------------------------------------

function retrieve_secret_byname {
    ##
    # retrieve_secret_byid $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #retrieve_secret_byname \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_name"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME

    #section "Begin: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    VAULT_MANAGEMENT_URL=https://$VAULT_REGION.kms.cloud.ibm.com/api/v2/keys
    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_MANAGEMENT_URL=$VAULT_MANAGEMENT_URL"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "-----------------"
    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"
    #echo "SECRET_NAME=$SECRET_NAME"
    #echo "-----------------"

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    #echo "Current list of vault secrets:"
    #echo "$VAULT_SECRETS"
    #echo "-----------------"

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has public facing ID:"
    #echo "$VAULT_SECRET_ID"
    #echo "-----------------"

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has Base64 Key Material:"
    #echo "$RETRIEVED_SECRET_MATERIAL"
    #echo "-----------------"

    #section "End: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    echo $RETRIEVED_SECRET_MATERIAL
}

## ----------------------------------------------------------------------------

function retrieve_secret_byid {
    ##
    # retrieve_secret_byid $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_ID
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #retrieve_secret_byid \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_id"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME

    #section "Begin: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    VAULT_MANAGEMENT_URL=https://$VAULT_REGION.kms.cloud.ibm.com/api/v2/keys
    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_MANAGEMENT_URL=$VAULT_MANAGEMENT_URL"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "-----------------"
    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"
    #echo "SECRET_NAME=$SECRET_NAME"
    #echo "-----------------"

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    #echo "Current list of vault secrets:"
    #echo "$VAULT_SECRETS"
    #echo "-----------------"

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has public facing ID:"
    #echo "$VAULT_SECRET_ID"
    #echo "-----------------"

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has Base64 Key Material:"
    #echo "$RETRIEVED_SECRET_MATERIAL"
    #echo "-----------------"

    #section "End: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    echo $RETRIEVED_SECRET_MATERIAL
}

## ----------------------------------------------------------------------------

function retrieve_secret_bydesc {
    ##
    # retrieve_secret_bydesc $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_DESC
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #retrieve_secret_bydesc \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_desc"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME

    #section "Begin: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    VAULT_MANAGEMENT_URL=https://$VAULT_REGION.kms.cloud.ibm.com/api/v2/keys
    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_MANAGEMENT_URL=$VAULT_MANAGEMENT_URL"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "-----------------"
    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"
    #echo "SECRET_NAME=$SECRET_NAME"
    #echo "-----------------"

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    #echo "Current list of vault secrets:"
    #echo "$VAULT_SECRETS"
    #echo "-----------------"

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has public facing ID:"
    #echo "$VAULT_SECRET_ID"
    #echo "-----------------"

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL
    #echo "New (or refetched) vault secret named '${SECRET_NAME}' has Base64 Key Material:"
    #echo "$RETRIEVED_SECRET_MATERIAL"
    #echo "-----------------"

    #section "End: retrieve_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    echo $RETRIEVED_SECRET_MATERIAL
}

## ----------------------------------------------------------------------------

function delete_secret {
    ##
    # delete_secret $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #delete_secret \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_name"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME

    #section "Begin: delete_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    VAULT_MANAGEMENT_URL=https://$VAULT_REGION.kms.cloud.ibm.com/api/v2/keys
    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_MANAGEMENT_URL=$VAULT_MANAGEMENT_URL"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "-----------------"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"
    #echo "SECRET_NAME=$SECRET_NAME"
    #echo "-----------------"

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    #echo "Current list of vault secrets:"
    #echo "$VAULT_SECRETS"
    #echo "-----------------"

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID
    #echo "Fetched vault secret named '${SECRET_NAME}' (for deletion) has public facing ID:"
    #echo "$VAULT_SECRET_ID"
    #echo "-----------------"

    # delete the specific vault secret itself...
    DELETE_SECRET_RESPONSE=$(curl -s -X DELETE ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID" \
    --header "Accept: application/vnd.ibm.kms.key+json")
    #check_value $DELETE_SECRET_RESPONSE

    #section "End: delete_secret: $VAULT_SERVICE_NAME :: $SECRET_NAME"

    echo $DELETE_SECRET_RESPONSE
}

## ----------------------------------------------------------------------------

function iam_writer_access {
    ##
    # iam_writer_access $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SOURCE_SERVICE_NAME $SOURCE_SERVICE_GUID
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #iam_writer_access \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_other_integrated_service_instance_name" \
    #  "my_other_integrated_service_instance_guid"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SOURCE_SERVICE_NAME=$4
    SOURCE_SERVICE_GUID=$5

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SOURCE_SERVICE_NAME
    check_value $SOURCE_SERVICE_GUID

    #section "Begin: iam_writer_access: $VAULT_SERVICE_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    #echo "-----------------"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "-----------------"

    PROCEED=0

    # the current User running this script will used as the owner of the service ID binding...
    TARGET_USER=$(ibmcloud target | grep User | awk '{print $2}')
    check_value "$TARGET_USER"
    #echo "TARGET_USER=$TARGET_USER"

    VAULT_IAM_SERVICE_ID_KEY_NAME=$VAULT_SERVICE_NAME-iam-service-id-$VAULT_GUID-$TARGET_USER
    check_value $VAULT_IAM_SERVICE_ID_KEY_NAME

    # create a service ID that will be used for an IAM binding of service A and B (the secrets management vault)...
    if check_exists "$(ibmcloud iam service-id $VAULT_IAM_SERVICE_ID_KEY_NAME 2>&1)"; then
      #echo "Reusing Service ID named '$VAULT_IAM_SERVICE_ID_KEY_NAME' as it already exists..."
      PROCEED=1
    else
      #echo "Creating new Service ID named '$VAULT_IAM_SERVICE_ID_KEY_NAME'..."
      ibmcloud iam service-id-create "$VAULT_IAM_SERVICE_ID_KEY_NAME" -d "serviceID for secrets management vault iam binding"
    fi
    SERVICE_ID=$(ibmcloud iam service-id "$VAULT_IAM_SERVICE_ID_KEY_NAME" --uuid)
    #echo "SERVICE_ID=$SERVICE_ID"
    check_value "$SERVICE_ID"
    
    EXISTING_POLICIES=$(ibmcloud iam service-policies $SERVICE_ID --output json)
    #echo "EXISTING_POLICIES=$EXISTING_POLICIES"
    check_value "$EXISTING_POLICIES"

    # create a policy (if it doesn't already exist) to make serviceID
    # a writer for the secrets management vault instance...
    if echo "$EXISTING_POLICIES" | \
      jq -e -r 'select(.[].resources[].attributes[].name=="serviceInstance" and .[].resources[].attributes[].value=="'$VAULT_GUID'" and .[].roles[].display_name=="Writer")' > /dev/null; then
        #echo "Writer policy on '$VAULT_SERVICE_NAME' already exist for the Service ID"
        PROCEED=1
    else
        #echo "Creating new Writer policy on '$VAULT_SERVICE_NAME' for the Service ID"
        ibmcloud iam service-policy-create $SERVICE_ID --roles Writer --service-name kms --service-instance $VAULT_GUID --force
    fi

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    #echo "VAULT_CREDENTIALS=$VAULT_CREDENTIALS"
    #echo "VAULT_IAM_APIKEY=$VAULT_IAM_APIKEY"
    #echo "VAULT_ACCESS_TOKEN=$VAULT_ACCESS_TOKEN"
    #echo "-----------------"

    # create the cross authorization between service A and B (the secrets management vault instance)...
    if ibmcloud iam authorization-policies | \
      grep -A 4 "Source service name:       $SOURCE_SERVICE_NAME" | \
      grep -A 3 "All instances" | \
      grep -A 2 "Target service name:       $VAULT_SERVICE_NAME" | \
      grep -q "Reader"; then
      #echo "Authorization policy exists"
      PROCEED=1
    else
      #echo "Authorization policy does not exist"
      ibmcloud iam authorization-policy-create \
        $SOURCE_SERVICE_NAME \
        $VAULT_SERVICE_NAME \
        Reader
    fi

    # grant Writer role for the source service to the secrets management vault serviceID...
    if ibmcloud iam service-policies $SERVICE_ID | grep -B 4 $SOURCE_SERVICE_GUID | grep Writer; then
      #echo "Writer policy on '$SOURCE_SERVICE_NAME' already exist for the secrets management vault service ID"
      PROCEED=1
    else
      #echo "Assigning Writer policy on '$SOURCE_SERVICE_NAME' to the secrets management vault service ID..."
      ibmcloud iam service-policy-create $SERVICE_ID --roles Writer --service-name $SOURCE_SERVICE_NAME --service-instance $SOURCE_SERVICE_GUID -f
    fi

    #section "End: iam_writer_access: $VAULT_SERVICE_NAME"
}

## ----------------------------------------------------------------------------

# get an instance of the secrets vault...
function get_vault_instance {
    ##
    # get_vault_instance $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #get_vault_instance \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP

    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "RESOURCE_GROUP=$RESOURCE_GROUP"
    #echo "-----------------"

    #section "Begin: get_vault_instance: $VAULT_SERVICE_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      #echo "Service named '$VAULT_SERVICE_NAME' already exists."
      PROCEED=1
    else
      #echo "Creating new instance of service named '$VAULT_SERVICE_NAME'..."
      ibmcloud resource service-instance-create $VAULT_SERVICE_NAME kms tiered-pricing $VAULT_REGION || exit 1
    fi

    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
    #echo "VAULT_GUID=$VAULT_GUID"
    #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
    #echo "-----------------"

    if check_exists "$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME 2>&1)"; then
      #echo "Service key named '$VAULT_SERVICE_SERVICE_KEY_NAME' already exists."
      PROCEED=1
    else
      #echo "Creating new service key named '$VAULT_SERVICE_SERVICE_KEY_NAME'..."
      ibmcloud resource service-key-create $VAULT_SERVICE_SERVICE_KEY_NAME Manager \
        --instance-id "$VAULT_INSTANCE_ID" || exit 1
    fi
    
    #section "End: get_vault_instance: $VAULT_SERVICE_NAME"
}

## ----------------------------------------------------------------------------

function delete_vault_instance {
    ##
    # delete_vault_instance $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #delete_vault_instance \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group"

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP

    #echo "VAULT_SERVICE_NAME=$VAULT_SERVICE_NAME"
    #echo "VAULT_REGION=$VAULT_REGION"
    #echo "RESOURCE_GROUP=$RESOURCE_GROUP"
    #echo "-----------------"

    #section "Begin: delete_vault_instance: $VAULT_SERVICE_NAME"

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    PROCEED=0

    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      #echo "Service named '$VAULT_SERVICE_NAME' exists - proceeding to delete this instance..."

      VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
      VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
      VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

      check_value $VAULT_INSTANCE_ID
      check_value $VAULT_GUID
      check_value $VAULT_SERVICE_SERVICE_KEY_NAME

      #echo "VAULT_INSTANCE_ID=$VAULT_INSTANCE_ID"
      #echo "VAULT_GUID=$VAULT_GUID"
      #echo "VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_SERVICE_KEY_NAME"
      #echo "-----------------"

      # now nuke the service instance and associated service id...
      ibmcloud resource service-instance-delete -f --recursive $VAULT_SERVICE_NAME
      ibmcloud iam service-id-delete -f $VAULT_SERVICE_SERVICE_KEY_NAME
    else
      #echo "Service named '$VAULT_SERVICE_NAME' doesn't exist in the '$VAULT_REGION' region so cannot delete it."
      PROCEED=1
    fi

    #section "End: delete_vault_instance: $VAULT_SERVICE_NAME"
}

## ----------------------------------------------------------------------------

# returns an IAM access token given an API key
function get_access_token {
  IAM_ACCESS_TOKEN_FULL=$(curl -s -k -X POST \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --header "Accept: application/json" \
  --data-urlencode "grant_type=urn:ibm:params:oauth:grant-type:apikey" \
  --data-urlencode "apikey=$1" \
  "https://iam.cloud.ibm.com/identity/token")
  IAM_ACCESS_TOKEN=$(echo "$IAM_ACCESS_TOKEN_FULL" | \
    grep -Eo '"access_token":"[^"]+"' | \
    awk '{split($0,a,":"); print a[2]}' | \
    tr -d \")
  echo $IAM_ACCESS_TOKEN
}

## ----------------------------------------------------------------------------

# returns a service CRN given a service name
function get_instance_id {
  OUTPUT=$(ibmcloud resource service-instance --output JSON $1)
  if (echo $OUTPUT | grep -q "crn:v1" >/dev/null); then
    echo $OUTPUT | jq -r .[0].id
  else
    echo "Failed to get instance ID: $OUTPUT"
    exit 2
  fi
}

## ----------------------------------------------------------------------------

# returns a service GUID given a service name
function get_guid {
  OUTPUT=$(ibmcloud resource service-instance --id $1)
  if (echo $OUTPUT | grep -q "crn:v1" >/dev/null); then
    echo $OUTPUT | awk -F ":" '{print $8}'
  else
    echo "Failed to get GUID: $OUTPUT"
    exit 2
  fi
}

## ----------------------------------------------------------------------------

# outputs a separator banner
function section {
  echo
  echo "####################################################################"
  echo "#"
  echo "# $1"
  echo "#"
  echo "####################################################################"
  echo
}

## ----------------------------------------------------------------------------

function check_exists {
  if echo "$1" | grep -q "not found"; then
    return 1
  fi
  if echo "$1" | grep -q "crn:v1"; then
    return 0
  fi
  echo "Failed to check if object exists: $1"
  exit 2
}

## ----------------------------------------------------------------------------

function check_value {
  if [ -z "$1" ]; then
    exit 1
  fi

  if echo $1 | grep -q -i "failed"; then
    exit 2
  fi
}

## ----------------------------------------------------------------------------
