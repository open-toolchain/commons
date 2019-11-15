#!/bin/bash
# uncomment to debug the script
# set -x

export BUILD_CLUSTER=${BUILD_CLUSTER:-"jumpstart"}
export BUILD_CLUSTER_NAMESPACE=${BUILD_CLUSTER_NAMESPACE:-"build"}
export IBMCLOUD_TARGET_REGION=${IBMCLOUD_TARGET_REGION:-"eu-gb"}

# if target region is in the 'ibm:yp:<region>' just keep the region part
REGION_SUBSET=$(echo "$IBMCLOUD_TARGET_REGION" | awk -F ':' '{print $3;}')
if [ -z "$REGION_SUBSET" ]; then
  echo "IBM Cloud Target Region is $IBMCLOUD_TARGET_REGION"
else
  export IBMCLOUD_TARGET_REGION=$REGION_SUBSET
  echo "IBM Cloud Target Region is $IBMCLOUD_TARGET_REGION. export IBMCLOUD_TARGET_REGION=$REGION_SUBSET done"
fi

echo "Logging in to build cluster account..."
ibmcloud login --apikey "$IBM_CLOUD_API_KEY" -r "$IBMCLOUD_TARGET_REGION"

if [ -z "$IBMCLOUD_TARGET_RESOURCE_GROUP" ]; then
  echo "Using default resource group" 
else
  ibmcloud target -g "$IBMCLOUD_TARGET_RESOURCE_GROUP"
fi

echo "Cluster list:"
ibmcloud ks clusters

echo "Running ibmcloud ks cluster-config -cluster "$BUILD_CLUSTER" --export"
CLUSTER_CONFIG_COMMAND=$(ibmcloud ks cluster-config -cluster "$BUILD_CLUSTER" --export)
echo "$CLUSTER_CONFIG_COMMAND"
eval $CLUSTER_CONFIG_COMMAND

echo "Checking cluster namespace $BUILD_CLUSTER_NAMESPACE"
if ! kubectl get namespace "$BUILD_CLUSTER_NAMESPACE"; then
  kubectl create namespace "$BUILD_CLUSTER_NAMESPACE"
fi

# Ensure there is a Docker server on the ${BUILD_CLUSTER}
if ! kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" rollout status -w deployment/docker; then
  echo "Installing Docker Server into build cluster..."
  kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" run docker --image=docker:18.09.2-dind --overrides='{ "apiVersion": "apps/v1", "spec": { "template": { "spec": {"containers": [ { "name": "docker", "image": "docker:18.09.2-dind", "securityContext": { "privileged": true } } ] } } } }'
  kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" rollout status -w deployment/docker
fi

# Use port-forward to make the pod/port locally accessible
# Be sure to use a running POD (not an evicted one)
kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" get pods 
kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" port-forward $(kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" get pods | grep docker | grep -i running | awk '{print $1;}') 2375:2375 > /dev/null 2>&1 &

while ! nc -z localhost 2375; do   
  sleep 0.1
done

export DOCKER_HOST='tcp://localhost:2375'

echo "Logging in to docker registry..."
ibmcloud cr login