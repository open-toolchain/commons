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
# Secrets Management Script Library API (Primary support for IBM Key Protect)
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
#   save_secret             :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $SECRET_MATERIAL
#   save_secret_hv          :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $SECRET_MATERIAL $VAULT_ADDR $VAULT_TOKEN_ID
#   generate_secret         :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $IS_ROOT_KEY
#   retrieve_secret         :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
#   retrieve_secret_hv      ::  $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $VAULT_ADDR $VAULT_TOKEN_ID
#   delete_secret           :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
#
#   ##rotate_secret           :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $POLICY
#   ##wrap_secret             :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
#   ##unwrap_secret           :: $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME
#
## ----------------------------------------------------------------------------

function save_secret {
    ##
    # save_secret $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $SECRET_MATERIAL
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #save_secret \
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

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    PROCEED=0

    ##
    # create an instance of the secrets management vault if it's not already there...
    ##
    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      # reusing secrets management vault service named '$VAULT_SERVICE_NAME' as it already exists...
      PROCEED=1
    else
      # creating new secrets management vault service instance named '$VAULT_SERVICE_NAME'...
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
      # reusing secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME' as it already exists...
      PROCEED=1
    else
      # creating new secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME'...
      ibmcloud resource service-key-create $VAULT_SERVICE_SERVICE_KEY_NAME Manager \
        --instance-id "$VAULT_INSTANCE_ID" || exit 1
    fi

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    # get a list of secrets on this vault secrets management instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    SECRET_MATERIAL=$(base64 -w 0 <<< $SECRET_MATERIAL)

    # now check if the we're trying to save a secret that already preexists...
    if echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'")' > /dev/null; then
      # reusing saved vault BYOK secret named '${SECRET_NAME}' as it already exists...
      PROCEED=1
    else
      # creating new vault BYOK secret named '$SECRET_NAME' with specified secret material...
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

      # retrieve the updated secrets list...
      VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
      --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
      --header "Bluemix-Instance: $VAULT_GUID")
      check_value $VAULT_SECRETS
    fi

    # extract the id of our newly saved (or refetched) secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID

    echo $VAULT_SECRET_ID
}

## ----------------------------------------------------------------------------

function save_secret_hv {
    ##
    # save_secret_hv $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP \
    #                $SECRET_NAME $SECRET_MATERIAL $VAULT_ADDR $VAULT_TOKEN_ID
    #
    #SECRET_ID=$(
    #    save_secret_hv \
    #        "vault kv" \
    #        null \
    #        null \
    #        "secret/hello" \
    #        "foo=bar" \
    #        "http://127.0.0.1:8200" \
    #        "s.EwQGhClLJKtEolWPpfz5XT1V" \
    #)

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2 #reserved
    RESOURCE_GROUP=$3 #reserved
    SECRET_NAME=$4
    SECRET_MATERIAL=$5

    if echo "$1" | grep -q "vault kv"; then
      export VAULT_ADDR=$6
      export VAULT_TOKEN_ID=$7
      VAULT_SECRET_ID=$(vault kv put ${SECRET_NAME} ${SECRET_MATERIAL})
    fi

    echo $VAULT_SECRET_ID
}

## ----------------------------------------------------------------------------

function generate_secret {
    ##
    # generate_secret $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP $SECRET_NAME $IS_STANDARD_KEY
    #

    ##
    # Typical usage:
    # --------------
    #source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")
    #generate_secret \
    #  "my_key_protect_instance_name" \
    #  "us-south" \
    #  "my_resource_group" \
    #  "my_secret_name" \
    #  true

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2
    RESOURCE_GROUP=$3
    SECRET_NAME=$4
    IS_STANDARD_KEY=$5

    check_value $VAULT_SERVICE_NAME
    check_value $VAULT_REGION
    check_value $RESOURCE_GROUP
    check_value $SECRET_NAME
    check_value $IS_STANDARD_KEY

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    PROCEED=0

    ##
    # create an instance of the secrets management vault if it's not already there...
    ##
    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      # reusing secrets management vault service named '$VAULT_SERVICE_NAME' as it already exists...
      PROCEED=1
    else
      # creating new secrets management vault service instance named '$VAULT_SERVICE_NAME'...
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
      # reusing secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME' as it already exists...
      PROCEED=1
    else
      # creating new secrets management vault service-key '$VAULT_SERVICE_SERVICE_KEY_NAME'...
      ibmcloud resource service-key-create $VAULT_SERVICE_SERVICE_KEY_NAME Manager \
        --instance-id "$VAULT_INSTANCE_ID" || exit 1
    fi

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    # now check if the we're trying to save a key that already preexists...
    if echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'")' > /dev/null; then
      # reusing saved vault auto secret named '${SECRET_NAME}' as it already exists..."
      PROCEED=1
    else
      # creating new vault auto secret named '$SECRET_NAME' with specified secret material..."
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
              "extractable": '${IS_STANDARD_KEY}'
            }
          ]
        }')
      check_value $NEW_VAULT_SECRET

      # retrieve the updated secrets list...
      VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
      --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
      --header "Bluemix-Instance: $VAULT_GUID")
      check_value $VAULT_SECRETS
    fi

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID

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

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL

    RETRIEVED_SECRET_MATERIAL=$(base64 -i -d <<< $RETRIEVED_SECRET_MATERIAL)

    echo $RETRIEVED_SECRET_MATERIAL
}

## ----------------------------------------------------------------------------

function retrieve_secret_hv {
    ##
    # retrieve_secret_hv $VAULT_SERVICE_NAME $VAULT_REGION $RESOURCE_GROUP \
    #                       $SECRET_NAME $VAULT_ADDR $VAULT_TOKEN_ID
    #
    #SECRET_VALUE=$(
    #    retrieve_secret_hv \
    #        "vault kv" \
    #        null \
    #        null \
    #        "secret/hello" \
    #        "http://127.0.0.1:8200" \
    #        "s.EwQGhClLJKtEolWPpfz5XT1V" \
    #)

    VAULT_SERVICE_NAME=$1
    VAULT_REGION=$2 #reserved
    RESOURCE_GROUP=$3 #reserved
    SECRET_NAME=$4

    if echo "$1" | grep -q "vault kv"; then
      export VAULT_ADDR=$5
      export VAULT_TOKEN_ID=$6
      RETRIEVED_SECRET_MATERIAL=$(vault kv get ${SECRET_NAME})
    fi

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

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL

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

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL

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

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID

    # retrieve the specific vault secret itself...
    VAULT_SECRET=$(curl -s ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRET
    RETRIEVED_SECRET_MATERIAL=$(echo "$VAULT_SECRET" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .payload')
    check_value $RETRIEVED_SECRET_MATERIAL

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

    # get a list of secrets on this vault secrets management service instance first...
    VAULT_SECRETS=$(curl -s $VAULT_MANAGEMENT_URL \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID")
    check_value $VAULT_SECRETS

    # extract the id of our newly saved (or refetched) auto secret...
    VAULT_SECRET_ID=$(echo "$VAULT_SECRETS" | jq -e -r '.resources[] | select(.name=="'${SECRET_NAME}'") | .id')
    check_value $VAULT_SECRET_ID

    # delete the specific vault secret itself...
    DELETE_SECRET_RESPONSE=$(curl -s -X DELETE ${VAULT_MANAGEMENT_URL}/${VAULT_SECRET_ID} \
    --header "Authorization: Bearer $VAULT_ACCESS_TOKEN" \
    --header "Bluemix-Instance: $VAULT_GUID" \
    --header "Accept: application/vnd.ibm.kms.key+json")

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

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_MANAGEMENT_URL
    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    PROCEED=0

    # the current User running this script will used as the owner of the service ID binding...
    TARGET_USER=$(ibmcloud target | grep User | awk '{print $2}')
    check_value "$TARGET_USER"

    VAULT_IAM_SERVICE_ID_KEY_NAME=$VAULT_SERVICE_NAME-iam-service-id-$VAULT_GUID-$TARGET_USER
    check_value $VAULT_IAM_SERVICE_ID_KEY_NAME

    # create a service ID that will be used for an IAM binding of service A and B (the secrets management vault)...
    if check_exists "$(ibmcloud iam service-id $VAULT_IAM_SERVICE_ID_KEY_NAME 2>&1)"; then
      # reusing Service ID named '$VAULT_IAM_SERVICE_ID_KEY_NAME' as it already exists...
      PROCEED=1
    else
      # creating new Service ID named '$VAULT_IAM_SERVICE_ID_KEY_NAME'...
      ibmcloud iam service-id-create "$VAULT_IAM_SERVICE_ID_KEY_NAME" -d "serviceID for secrets management vault iam binding"
    fi
    SERVICE_ID=$(ibmcloud iam service-id "$VAULT_IAM_SERVICE_ID_KEY_NAME" --uuid)
    check_value "$SERVICE_ID"
    
    EXISTING_POLICIES=$(ibmcloud iam service-policies $SERVICE_ID --output json)
    check_value "$EXISTING_POLICIES"

    # create a policy (if it doesn't already exist) to make serviceID
    # a writer for the secrets management vault instance...
    if echo "$EXISTING_POLICIES" | \
      jq -e -r 'select(.[].resources[].attributes[].name=="serviceInstance" and .[].resources[].attributes[].value=="'$VAULT_GUID'" and .[].roles[].display_name=="Writer")' > /dev/null; then
        # writer policy on '$VAULT_SERVICE_NAME' already exist for the Service ID"...
        PROCEED=1
    else
        # creating new Writer policy on '$VAULT_SERVICE_NAME' for the Service ID"...
        ibmcloud iam service-policy-create $SERVICE_ID --roles Writer --service-name kms --service-instance $VAULT_GUID --force
    fi

    VAULT_CREDENTIALS=$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME --output JSON)
    check_value $VAULT_CREDENTIALS
    VAULT_IAM_APIKEY=$(echo "$VAULT_CREDENTIALS" | jq -r .[0].credentials.apikey)
    check_value $VAULT_IAM_APIKEY
    VAULT_ACCESS_TOKEN=$(get_access_token $VAULT_IAM_APIKEY)
    check_value $VAULT_ACCESS_TOKEN

    # create the cross authorization between service A and B (the secrets management vault instance)...
    if ibmcloud iam authorization-policies | \
      grep -A 4 "Source service name:       $SOURCE_SERVICE_NAME" | \
      grep -A 3 "All instances" | \
      grep -A 2 "Target service name:       $VAULT_SERVICE_NAME" | \
      grep -q "Reader"; then
      # authorization policy exists...
      PROCEED=1
    else
      # authorization policy does not exist...
      ibmcloud iam authorization-policy-create \
        $SOURCE_SERVICE_NAME \
        $VAULT_SERVICE_NAME \
        Reader
    fi

    # grant Writer role for the source service to the secrets management vault serviceID...
    if ibmcloud iam service-policies $SERVICE_ID | grep -B 4 $SOURCE_SERVICE_GUID | grep Writer; then
      # writer policy on '$SOURCE_SERVICE_NAME' already exist for the secrets management vault service ID...
      PROCEED=1
    else
      # assigning Writer policy on '$SOURCE_SERVICE_NAME' to the secrets management vault service ID...
      ibmcloud iam service-policy-create $SERVICE_ID --roles Writer --service-name $SOURCE_SERVICE_NAME --service-instance $SOURCE_SERVICE_GUID -f
    fi
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

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      # service named '$VAULT_SERVICE_NAME' already exists...
      PROCEED=1
    else
      # creating new instance of service named '$VAULT_SERVICE_NAME'...
      ibmcloud resource service-instance-create $VAULT_SERVICE_NAME kms tiered-pricing $VAULT_REGION || exit 1
    fi

    VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
    VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
    VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

    check_value $VAULT_INSTANCE_ID
    check_value $VAULT_GUID
    check_value $VAULT_SERVICE_SERVICE_KEY_NAME

    if check_exists "$(ibmcloud resource service-key $VAULT_SERVICE_SERVICE_KEY_NAME 2>&1)"; then
      # service key named '$VAULT_SERVICE_SERVICE_KEY_NAME' already exists...
      PROCEED=1
    else
      # creating new service key named '$VAULT_SERVICE_SERVICE_KEY_NAME'...
      ibmcloud resource service-key-create $VAULT_SERVICE_SERVICE_KEY_NAME Manager \
        --instance-id "$VAULT_INSTANCE_ID" || exit 1
    fi
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

    ibmcloud target -g $RESOURCE_GROUP > /dev/null

    PROCEED=0

    if check_exists "$(ibmcloud resource service-instance $VAULT_SERVICE_NAME 2>&1)"; then
      # service named '$VAULT_SERVICE_NAME' exists - proceeding to delete this instance..."

      VAULT_INSTANCE_ID=$(get_instance_id $VAULT_SERVICE_NAME)
      VAULT_GUID=$(get_guid $VAULT_SERVICE_NAME)
      VAULT_SERVICE_SERVICE_KEY_NAME=$VAULT_SERVICE_NAME-service-key-$VAULT_GUID

      check_value $VAULT_INSTANCE_ID
      check_value $VAULT_GUID
      check_value $VAULT_SERVICE_SERVICE_KEY_NAME

      # now nuke the service instance and associated service id...
      ibmcloud resource service-instance-delete -f --recursive $VAULT_SERVICE_NAME
      ibmcloud iam service-id-delete -f $VAULT_SERVICE_SERVICE_KEY_NAME
    else
      # service named '$VAULT_SERVICE_NAME' doesn't exist in the '$VAULT_REGION' region so cannot delete it...
      PROCEED=1
    fi
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
