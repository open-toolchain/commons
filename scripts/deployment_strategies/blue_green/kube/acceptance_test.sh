#!/bin/bash
source ./pipeline.data
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}
echo "Acceptance url $ACCEPTANCE_TEST_URL"
if curl --head --silent --fail ${ACCEPTANCE_TEST_URL} 2> /dev/null;
 then
   echo "Acceptance test passed........";
 else
   echo "Acceptance test failed........"
   exit 1
fi
