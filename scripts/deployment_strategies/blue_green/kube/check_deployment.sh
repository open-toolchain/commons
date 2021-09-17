#!/bin/bash

echo -e "CHECKING deployment rollout of ${DEPLOYMENT_NAME}"
echo ""

if kubectl rollout status deploy/${DEPLOYMENT_NAME} --watch=true --timeout=${ROLLOUT_TIMEOUT:-"150s"} --namespace ${CLUSTER_NAMESPACE}; then
  STATUS="pass"
else
  STATUS="fail"
fi

pipeline_data="pipeline.data"
{
  echo "export CLUSTER_NAMESPACE=\"${CLUSTER_NAMESPACE}\""
} >> "$pipeline_data"

