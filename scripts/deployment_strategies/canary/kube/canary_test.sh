#!/bin/bash
source ./pipeline.data

kubectl config set-context --current --namespace=${CLUSTER_NAMESPACE}
INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson ${DEPLOYMENT_FILE} | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
echo $ACCEPTANCE_TEST_URL
echo $INGRESS_DOC_INDEX
echo $CANARY_DEPLOYMENT_FILE
echo "STEP_SIZE  $STEP_SIZE"
echo "STEP_INTERVAL  $STEP_INTERVAL"


function perform_test() {
    WEIGHT_SIZE=$1

   
    if  kubectl get svc  ${CANARY_NODEPORT_SERVICE_NAME} -o json | grep '"deployment": "stop"' ;
    then
        echo "Canary Deployment abort triggered. Exiting Canary Deployment."
        exit 1
    else 
        echo "Testing canary deployment"
        if [ $(curl -LI  ${ACCEPTANCE_TEST_URL} -o /dev/null -w '%{http_code}\n' -s) == "200" ];
        then
            echo "Canary test passed.";
            echo "Increasing the weight of canary deployment ${WEIGHT_SIZE}.";
            yq w --inplace --doc  $INGRESS_DOC_INDEX $CANARY_DEPLOYMENT_FILE metadata.annotations.[nginx.ingress.kubernetes.io/canary-weight] \"${WEIGHT_SIZE}\"
            kubectl apply -f $CANARY_DEPLOYMENT_FILE
            sleep $STEP_INTERVAL
        else 
            echo "Canary tests failed."
            exit 1
        fi
    fi    
}

if  kubectl get ing | grep  ${CANARY_INGRESS_NAME};
    then
      for (( c=0; c<=100; c=c+STEP_SIZE ))
      do  
        echo "Performing canary test $c "
        perform_test $c
      done
    else 
        echo "This is the first Deployment of the application."
    fi

