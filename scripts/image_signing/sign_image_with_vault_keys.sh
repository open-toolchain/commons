
#!/bin/bash
#Requires
#VAULT_INSTANCE -name of vault
# $IBMCLOUD_TARGET_REGION -region hosting Key Protect Vault instance
# $IBMCLOUD_TARGET_RESOURCE_GROUP of the Key Protect Vault Instance
# REGISTRY_NAMESPACE namespace of registry
# $IMAGE_NAME
# $IMAGE_TAG
# $DEVOPS_SIGNER
export DOCKER_CONTENT_TRUST=1
echo "Vault instance $VAULT_INSTANCE used to retrieve signing keys"
source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/image_signing/signing_utils.sh")
# Restore signer pem key
VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")
JSON_DATA="$(readData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA")"
signerkey=$(getJSONValue "$DEVOPS_SIGNER" "$JSON_DATA")
writeFile "$signerkey"
# Retrieve the signer passphrase
export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$(getJSONValue "passphrase" "$signerkey")

export DCT_DISABLED=false
# Pull the image
docker pull "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
# Sign the image
docker trust sign "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
docker trust inspect --pretty "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
