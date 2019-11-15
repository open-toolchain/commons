#!/bin/bash
# uncomment to debug the script
# set -x

if [ -z "$REGISTRY_URL" ]; then
  # Use the ibmcloud cr info to find the target registry url 
  export REGISTRY_URL=$(ibmcloud cr info | grep -m1 -i '^Container Registry' | awk '{print $3;}')
fi

cise_crd_template=$(cat <<'EOT'
apiVersion: securityenforcement.admission.cloud.ibm.com/v1beta1
kind: %s
metadata:
  name: %s
spec:
  repositories:
  - name: %s
    policy:
      trust:
        enabled: %s
        signerSecrets:
        - name: %s
      va:
        enabled: %s
EOT
)

createCISE_CRD() {
    printf "$cise_crd_template" \
    "ImagePolicy" \
    "$REGISTRY_NAMESPACE.$IMAGE_NAME.$DEVOPS_SIGNER" \
    "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME" \
    "true" \
    "$REGISTRY_NAMESPACE.$IMAGE_NAME.$DEVOPS_SIGNER" \
    "true"
}
