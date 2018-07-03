#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/wait_deploy_umbrella.sh) and 'source' it from your pipeline job
#    source ./scripts/wait_deploy_umbrella.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/wait_deploy_umbrella.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/wait_deploy_umbrella.sh
# Input env variables (can be received via a pipeline environment properties.file.
echo "CHART_PATH=${CHART_PATH}"

if [ -f build.properties ]; then 
  echo "build.properties:"
  cat build.properties
else 
  echo "build.properties : not found"
fi 
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://console.bluemix.net/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

# Input env variables from pipeline job
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

# Infer CHART_NAME from path to chart (last segment per construction for valid charts)
CHART_NAME=$(basename $CHART_PATH)

echo "=========================================================="
echo "Required env vars:"
if [ -z "$CLUSTER_NAMESPACE" ]; then
  echo "One of the required env vars is missing"
  exit -1
fi
ls -al charts

echo "=========================================================="
echo -e "Extracting component charts"
mkdir -p temp_charts
for tarfile in charts/*.tgz ; do
    echo $tarfile
    tar -xf $tarfile -C temp_charts/
done
echo "=========================================================="
echo ""
echo "=========================================================="
echo -e "Cheking deployment status of the following components:"
COMPONENTS_REPOS_TAGS=
for file in $(find temp_charts -maxdepth 2 -type f -name values.yaml); 
do 
    IMAGE=$(awk '/image:/,/tag:/' $file)
    IMAGE_TAG=$(echo "$IMAGE" | grep "tag:" | awk 'NF==2' | awk '{print $2;}') # awk 'NF==2' is to workaround some components that have 2 "tags:"" entries, one being empty
    IMAGE_REPOSITORY=$(echo "$IMAGE" | grep "repository:" | awk '{print $2;}')
    if [[ -z "$IMAGE_REPOSITORY" ]]; then
        # repository: is set for pipeline components, other components define registry: and name:
        IMAGE_REGISTRY=$(echo "$IMAGE" | grep "registry:" | awk 'NF==2' | awk '{print $2;}')
        if [[ -z "$IMAGE_REGISTRY" ]]; then
            >&2 echo "No image.registry found in $file"
            continue; #malformed, ignore
        fi
        IMAGE_NAME=$(echo "$IMAGE" | grep "name:" | awk 'NF==2' | awk '{print $2;}')
        if [[ -z "$IMAGE_NAME" ]]; then
            >&2 echo "No image.name found in $file"
            continue; #malformed, ignore
        fi
        IMAGE_REPOSITORY=$IMAGE_REGISTRY/$IMAGE_NAME
    fi
    COMPONENT_NAME=$(echo $file | awk '{n=split($1,a,"/"); print a[n-1];}')
    echo "$COMPONENT_NAME:$IMAGE_REPOSITORY:$IMAGE_TAG"
    COMPONENTS_REPOS_TAGS=$COMPONENTS_REPOS_TAGS$COMPONENT_NAME:$IMAGE_REPOSITORY:$IMAGE_TAG$'\n'
done
echo "=========================================================="
echo -e "Expected number of replicas:"
COMPONENTS_AND_REPLICAS=$( grep -r "replicaCount:" temp_charts/*/values.yaml | awk '{if ( $NF ~ /[0-9]/ ) { n=split($1,a,"/"); print a[n-1] ":" $NF; }}' )
echo -e "${COMPONENTS_AND_REPLICAS}"
echo "=========================================================="
MAX=${WAIT_FOR_DEPLOY_MAX:-30}
for ((ITERATION = 1 ; ITERATION <= $MAX ; ITERATION++ ));
do
    echo -e ""
    STATUS=DONE
    NOT_READY_COMPONENTS=
    echo -e "Retrieving pods in namespace ${CLUSTER_NAMESPACE}"
    ALL_PODS=$( kubectl get pods --namespace ${CLUSTER_NAMESPACE} -o json )
    for COMPONENT_REPO_TAG in ${COMPONENTS_REPOS_TAGS}
    do
        IFS=':' read COMPONENT_NAME IMAGE_REPOSITORY IMAGE_TAG <<< $COMPONENT_REPO_TAG
        COMPONENT_AND_REPLICA=$( echo "${COMPONENTS_AND_REPLICAS}" | grep ${COMPONENT_NAME} )
        IFS=':' read unused REPLICA <<< $COMPONENT_AND_REPLICA
        if [[ "${REPLICA}" -eq "0" ]]; then
            continue;
        fi
        COMPONENT_PODS=$( echo $ALL_PODS | jq '.items[]?.status.containerStatuses[] | select(.image | startswith("'"${IMAGE_REPOSITORY}"'")) ' ) # []? - see https://github.ibm.com/org-ids/roadmap/issues/6264
        if [[ -z "$COMPONENT_PODS" ]]; then
            NOT_READY_COMPONENTS="${NOT_READY_COMPONENTS}${COMPONENT_NAME} "
            >&2 echo -e "${COMPONENT_NAME}: No pods deployed for this component, expecting ${REPLICA}"
            STATUS=DEPLOYING
        else
            IMAGE_PODS=$( echo $COMPONENT_PODS | jq '. | select(.image=="'"${IMAGE_REPOSITORY}:${IMAGE_TAG}"'") ' )
            if [[ -z "$IMAGE_PODS" ]]; then
                NOT_READY_COMPONENTS="${NOT_READY_COMPONENTS}${COMPONENT_NAME} "
                >&2 echo -e "${COMPONENT_NAME}: No pods deployed with image ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
                STATUS=DEPLOYING
            else
                NOT_READY_PODS=$( echo $IMAGE_PODS | jq '. | select(.ready==false) ' )
                if [[ -z "$NOT_READY_PODS" ]]; then
                    echo -e "${COMPONENT_NAME}: All pods are ready."
                else
                    NOT_READY_COMPONENTS="${NOT_READY_COMPONENTS}${COMPONENT_NAME} "
                    REASON=$(echo $NOT_READY_PODS | jq '. | .state.waiting.reason')
                    echo -e "${ITERATION} : Deployment still pending..."
                    echo -e "NOT_READY_PODS:${NOT_READY_PODS}"
                    echo -e "REASON: ${REASON}"
                    if [[ "${REASON}" == *"ErrImagePull"* ]] || [[ "${REASON}" == *"ImagePullBackOff"* ]]; then
                        echo "${COMPONENT_NAME}: Detected ErrImagePull or ImagePullBackOff failure. "
                        echo "Please check proper authenticating to from cluster to image registry (e.g. image pull secret)"
                        STATUS=FAILED
                        break; # no need to wait longer, error is fatal
                    elif [[ "${REASON}" == *"CrashLoopBackOff"* ]]; then
                        echo "${COMPONENT_NAME}: Detected CrashLoopBackOff failure. "
                        echo "Application is unable to start, check the application startup logs"
                        STATUS=FAILED
                        break; # no need to wait longer, error is fatal
                    fi
                    >&2 echo -e "${COMPONENT_NAME}: Not all pods are ready for image ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
                    STATUS=DEPLOYING
                fi
            fi
        fi
    done
    if [[ "${STATUS}" == "DEPLOYING" ]]; then
        if [[ "$ITERATION" -lt "$MAX" ]]; then
            echo -e "Retrying in 5s... (${ITERATION}/${MAX})"
            sleep 5
        else
            >&2 echo -e "Giving up after $MAX iterations"
        fi
    else
        break;
    fi
done

if [[ "$STATUS" != "DONE" ]]; then
  echo ""
  echo "=========================================================="
  echo "DEPLOYMENT FAILED"
  echo "Not ready services:"
  for NOT_READY in ${NOT_READY_COMPONENTS}
  do
    kubectl describe services ${NOT_READY} --namespace ${CLUSTER_NAMESPACE}
    echo " "
  done
  echo "----------------------------------------------------------"
  echo "Not ready pods:"
  for NOT_READY in ${NOT_READY_COMPONENTS}
  do
    kubectl describe pods ${NOT_READY} --namespace ${CLUSTER_NAMESPACE}
    echo " "
  done
  echo "=========================================================="
  #exit 1
else
  echo ""
  echo "=========================================================="
  echo "DEPLOYMENT SUCCEEDED"
  echo "=========================================================="
fi