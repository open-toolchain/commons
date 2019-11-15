#!/bin/bash
# uncomment to debug the script
# set -x

if [ -z "$REGISTRY_URL" ]; then
  # Use the ibmcloud cr info to find the target registry url 
  export REGISTRY_URL=$(ibmcloud cr info | grep -m1 -i '^Container Registry' | awk '{print $3;}')
fi
export REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:-'jumpstart'}
export IMAGE_NAME=${IMAGE_NAME:-'signed-hello-app'}

export GUN="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
export DOCKER_CONTENT_TRUST_SERVER=${DOCKER_CONTENT_TRUST_SERVER:-"https://$REGISTRY_URL:4443"}
echo "DOCKER_CONTENT_TRUST_SERVER=$DOCKER_CONTENT_TRUST_SERVER"

# Notary Setup usage avec DCT
# https://github.com/theupdateframework/notary/blob/master/docs/command_reference.md#set-up-notary-cli

export DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE=${DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE:-"dctrootpassphrase"}
export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=${DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE:-"dctrepositorypassphrase"}

export NOTARY_ROOT_PASSPHRASE="$DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE"
export NOTARY_TARGETS_PASSPHRASE="$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE"
export NOTARY_SNAPSHOT_PASSPHRASE="$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE"
export NOTARY_AUTH=$(echo -e "iamapikey:$IBM_CLOUD_API_KEY" | base64)

# repository init for the GUN (repo/namespace/image) using notary
notary -s $DOCKER_CONTENT_TRUST_SERVER -d ~/.docker/trust init "$GUN"
if notary -s $DOCKER_CONTENT_TRUST_SERVER -d ~/.docker/trust publish "$GUN"; then
  echo "$GUN initialized and published using notary"
else
  echo "Failure during $GUN initialization and publish"
  exit 1;
fi

# remove/revoke the snapshot delegation in order for the delegation to not need the snapshot key
# https://docs.docker.com/notary/advanced_usage/#rotate-keys
notary -s $DOCKER_CONTENT_TRUST_SERVER -d ~/.docker/trust key rotate "$GUN" snapshot -r
notary -s $DOCKER_CONTENT_TRUST_SERVER -d ~/.docker/trust publish "$GUN"

# If $ARCHIVE_DIR then create the tar file containing certificates/keys created during initialization
# https://docs.docker.com/engine/security/trust/trust_key_mng/#back-up-your-keys , add public key
# and specific information for DCT initialization
if [[ "$ARCHIVE_DIR" ]]; then
    mkdir -p $ARCHIVE_DIR
    echo "GUN=$GUN" > $ARCHIVE_DIR/dct.properties
    echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/dct.properties
    echo "REGISTRY_REGION=${REGISTRY_REGION}" >> $ARCHIVE_DIR/dct.properties
    echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/dct.properties
    echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/dct.properties
    echo "DOCKER_CONTENT_TRUST_SERVER=$DOCKER_CONTENT_TRUST_SERVER" >> $ARCHIVE_DIR/dct.properties

    # if no vault is configured, keep the passphrase and backup the keys in the archive
    # https://docs.docker.com/engine/security/trust/trust_key_mng/#back-up-your-keys
    if [ -z "$VAULT_INSTANCE" ]; then
      echo "No Vault instance defined - backing-up the keys in $ARCHIVE_DIR directory"
      echo "DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE=$DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE" >> $ARCHIVE_DIR/dct.properties	
      echo "DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE" >> $ARCHIVE_DIR/dct.properties	
      umask 077; tar -zcvf $ARCHIVE_DIR/private_keys_backup.tar.gz --directory ~ .docker/trust/private; umask 022    
    else 
      echo "Vault instance $VAULT_INSTANCE defined - it would be used for the key backup"
    fi
fi