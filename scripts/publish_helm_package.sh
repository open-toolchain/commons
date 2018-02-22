#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/publish_helm_package.sh) and 'source' it from your pipeline job
#    source ./scripts/publish_helm_package.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_helm_package.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/publish_helm_package.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "GIT_USER=${GIT_USER}"
echo "GIT_PASSWORD=${GIT_PASSWORD}"
echo "UMBRELLA_REPO_NAME=${UMBRELLA_REPO_NAME}"
echo "CHART_NAME=${CHART_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"

#View build properties
# cat build.properties
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

#***********************************************************************************
git clone https://$GIT_USER:$GIT_PASSWORD@github.ibm.com/$CHART_ORG/$CHART_REPO
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
git config --global user.email "idsorg@us.ibm.com"
git config --global user.name "IDS Organization"
git config --global push.default matching

CHART_REPO_ABS=$(pwd)/$CHART_REPO

echo "Discovery Registry..."
REGISTRY=$(bx cr info | grep 'Container Registry  ' | awk '{print $3};')
echo "Found: $REGISTRY"

echo "Discover OpenToolchain Registry Token..."
TOKEN=$(bx cr token-get -q "$REGISTRY_TOKEN_ID")
echo "Found"

echo "Registry Namespace ..."
echo $REGISTRY_NAMESPACE

echo "Image Name ..."
echo $IMAGE_NAME

echo "Discovery $IMAGE_TAG version..."
VERSION=$(bx cr images --format "{{if and (eq .Tag \"$IMAGE_TAG\") (eq .Repository \"$REGISTRY/$REGISTRY_NAMESPACE/$IMAGE_NAME\")}}{{.Digest}}{{end}}" | while read line; do bx cr images --format "{{if and (and (eq .Digest \"${line}\") (ne .Tag \"latest\")) (ne .Tag \"test_passed\")}}{{.Tag}}{{end}}"; done)
echo "Found: $VERSION"
if [ -z "$VERSION" ]; then
  echo "No version with $IMAGE_TAG"
  exit 1
fi

#if grep -q $VERSION $CHART_REPO/charts/index.yaml; then
#  echo "Package with image $VERSION already published!"
#  exit 0
#fi

if [ -z "$CONTAINER_BUILD_NUMBER" ]; then
  echo "Overriding image build number with: $VERSION"
  export ENV_BUILD_NUMBER=$VERSION
else
  if [ "$CONTAINER_BUILD_NUMBER" = 'false' ]; then
    echo "Using image's build number"
  else
    echo "Overriding Container build number with: $CONTAINER_BUILD_NUMBER"
    export ENV_BUILD_NUMBER=$CONTAINER_BUILD_NUMBER
  fi 
fi
if [ "$CHECKOUT_CHART" = 'true' ]; then
  echo "Pulling Helm Chart corresponding to docker image $VERSION ..."
  git checkout -q $(echo $VERSION | cut -d'-' -f 1)
fi
values_template=$(cat <<EOT
clusterSubDomain: %s
clusterSecret: %s
image:
  name: %s/%s
  registry: %s
  token: %s
  tag: %s
  pullPolicy: IfNotPresent
restartPolicy: Never
region: ng
replicas: %s
env:
%s
secrets:
%s
global:
  clusterSubDomain: %s
  clusterSecret: %s
  env:
%s
  secrets:
%s
%s
EOT
)
echo "$values_template"
cd k8s
if [ -z "$DOMAIN" ]; then
  DOMAIN=$(bx cs cluster-get -s $PIPELINE_KUBERNETES_CLUSTER_NAME | grep "Ingress subdomain:" | awk '{print $3;}')
fi

if [ -z "$INGRESS_SECRET" ]; then
  INGRESS_SECRET=$(bx cs cluster-get -s $PIPELINE_KUBERNETES_CLUSTER_NAME | grep "Ingress secret:" | awk '{print $3;}')
fi

# Inline secured values by default - temporary workaround until every pipeline jobs have been reviewed and updated
INLINE_SECURED_VALUES=${INLINE_SECURED_VALUES:-"true"}
if [ "$INLINE_SECURED_VALUES" = "true" ]; then
  printf "$values_template" "$DOMAIN" "$INGRESS_SECRET" "$REGISTRY_NAMESPACE" "$IMAGE_NAME" "$REGISTRY" "$TOKEN" "$VERSION" "$NUM_INSTANCES" "$(compgen -v | grep ENV_ | while read line; do echo "  ${line:4}: ${!line}";done)" "$(compgen -v | grep SEC_ | while read line; do echo "  ${line:4}: ${!line}";done)" "$DOMAIN" "$INGRESS_SECRET" "$(compgen -v | grep GLOBAL_ENV_ | while read line; do echo "    ${line:11}: ${!line}";done)" "$(compgen -v | grep GLOBAL_SEC_ | while read line; do echo "    ${line:11}: ${!line}";done)" "$EXTRA" >> $IMAGE_NAME/values.yaml
else 
  printf "$values_template" "$DOMAIN" "$INGRESS_SECRET" "$REGISTRY_NAMESPACE" "$IMAGE_NAME" "$REGISTRY" "$TOKEN" "$VERSION" "$NUM_INSTANCES" "$(compgen -v | grep ENV_ | while read line; do echo "  ${line:4}: ${!line}";done)" "$(compgen -v | grep SEC_ | while read line; do echo "  ${line:4}: \"\"";done)" "$DOMAIN" "$INGRESS_SECRET" "$(compgen -v | grep GLOBAL_ENV_ | while read line; do echo "    ${line:11}: ${!line}";done)" "$(compgen -v | grep GLOBAL_SEC_ | while read line; do echo "    ${line:11}: \"\"";done)" "$EXTRA" >> $IMAGE_NAME/values.yaml
fi

echo "appVersion: $VERSION" >> $IMAGE_NAME/Chart.yaml
echo "version: $MAJOR_VERSION.$MINOR_VERSION.$BUILD_NUMBER" >> $IMAGE_NAME/Chart.yaml
# Temp upgrade to Helm 2.8; to be removed after pipeline base image update
wget https://storage.googleapis.com/kubernetes-helm/helm-v2.8.0-linux-amd64.tar.gz
tar -xzvf helm-v2.8.0-linux-amd64.tar.gz
mkdir $HOME/helm28
mv linux-amd64/helm $HOME/helm28/
export PATH=$HOME/helm28:$PATH
#
helm init -c

echo "=========================================================="
echo "Checking Helm Chart"
if helm lint --strict ${RELEASE_NAME} ${IMAGE_NAME}; then
  echo "helm lint done"
else
  echo "helm lint failed"
  echo "Currently helm linting won't fail the build." 
  #exit 1
fi

echo -e "Dry run into: ${PIPELINE_KUBERNETES_CLUSTER_NAME}/${NAMESPACE}."
if helm upgrade ${RELEASE_NAME} ${IMAGE_NAME} --namespace $NAMESPACE --install --dry-run; then
  echo "helm upgrade --dry-run done"
else
  echo "helm upgrade --dry-run failed"
  exit 1
fi

git -C $CHART_REPO_ABS pull --no-edit

echo "Packaging Helm Chart"

mkdir -p $CHART_REPO_ABS/charts
helm package ${IMAGE_NAME} -d $CHART_REPO_ABS/charts

cd $CHART_REPO_ABS

echo "Updating Helm Chart Repository index"
touch charts/index.yaml
helm repo index charts --merge charts/index.yaml --url https://$IDS_TOKEN@raw.github.ibm.com/$CHART_ORG/$CHART_REPO/master/charts

git add .
git commit -m "$VERSION"
git push
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

if [ -n "$TRIGGER_BRANCH" ]; then
  echo "Triggering CD pipeline ..."
  mkdir trigger
  cd trigger
  git clone https://$IDS_USER:$IDS_TOKEN@github.ibm.com/$CHART_ORG/$CHART_REPO -b $TRIGGER_BRANCH
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
  cd $CHART_REPO
  printf "On $(date), published helm chart for $RELEASE_NAME ($VERSION)" > trigger.txt
  git add .
  git commit -m "Published $RELEASE_NAME ($VERSION)"
  git push
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
  echo "CD pipeline triggered"
fi