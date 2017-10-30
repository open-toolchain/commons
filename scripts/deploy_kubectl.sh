#!/bin/bash
#set -x
#Check cluster availability
ip_addr=$(bx cs workers $PIPELINE_KUBERNETES_CLUSTER_NAME | grep normal | awk '{ print $2 }')
if [ -z $ip_addr ]; then
echo "$PIPELINE_KUBERNETES_CLUSTER_NAME not created or workers not ready"
exit 1
fi
#Connect to a different container-service api by uncommenting and specifying an api endpoint
#bx cs init --host https://us-south.containers.bluemix.net
echo ""
echo "DEPLOYING USING MANIFEST:"
cat deployment.yml
kubectl apply -f deployment.yml  
echo ""
echo "DEPLOYED SERVICE:"
kubectl describe services hello-service
echo ""
echo "DEPLOYED PODS:"
kubectl describe pods --selector app=hello-app
port=$(kubectl get services | grep hello-service | sed 's/.*:\([0-9]*\).*/\1/g')
echo ""
echo "VIEW THE APPLICATION AT: http://$ip_addr:$port"