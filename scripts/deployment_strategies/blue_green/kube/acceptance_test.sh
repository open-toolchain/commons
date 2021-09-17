#!/bin/bash
source ./pipeline.data
kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}
echo $ACCEPTANCE_TEST_URL
if [ $(curl -LI  ${ACCEPTANCE_TEST_URL} -o /dev/null -w '%{http_code}\n' -s) == "200" ];
then
    echo "Acceptance test passed........";
else 
    echo "Acceptance test failed........"
    exit 1
 fi