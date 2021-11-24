
#!/bin/bash

# This script checks if cluster group contains mix of IKS and openshift clusters.
# If Cluster group contains mix of IKS and openshift. It will throw the error.
# To use this script, export the env variable SATELLITE_CLUSTER_GROUP with cluster group.

CLUSTERNAME=$(ibmcloud sat group get --group "${SATELLITE_CLUSTER_GROUP}" -output json | jq -r '.clusters[0].registration.name')
CLUSTERVERSION=$(ibmcloud sat cluster ls --output json | jq ".clusterSearch[] | select(.metadata.name==\"$CLUSTERNAME\") | .metadata.kube_version.gitVersion")

CLUSTER_LIST=$(ibmcloud sat group get --group "${SATELLITE_CLUSTER_GROUP}" -output json | jq -r '.clusters[].registration.name')
list=($CLUSTER_LIST)

# Get version of a cluster at zero position.
CURRENTVERSION=$(ibmcloud sat cluster ls --output json | jq ".clusterSearch[] | select(.metadata.name==\"${list[0]}\") | .metadata.kube_version.gitVersion")

if [[ $CURRENTVERSION =~ "IKS" ]]; then
    echo "Check if all the clusters are IKS clusters."
    for ((i = 0; i < ${#list[@]}; i++)); do
        VERSION=$(ibmcloud sat cluster ls --output json | jq ".clusterSearch[] | select(.metadata.name==\"${list[$i]}\") | .metadata.kube_version.gitVersion")
        if [[ $VERSION =~ "IKS" ]]; then
            echo "${list[$i]} is an IKS Cluster. Version:- $VERSION Continue..."
        else
            echo "Cluster group contains mix of clusters both of type IKS and OpenShift."
            echo "This deployment script only supports a cluster group of only one type. i.e a cluster group of IKS only or OpenShift."
            exit 1
        fi

    done
else

    echo "Check if all the clusters are IKS clusters."
    for ((i = 0; i < ${#list[@]}; i++)); do
        VERSION=$(ibmcloud sat cluster ls --output json | jq ".clusterSearch[] | select(.metadata.name==\"${list[$i]}\") | .metadata.kube_version.gitVersion")
        if [[ $VERSION =~ "IKS" ]]; then
            echo "Cluster group contains clusters of type IKS and Openshift."
            echo "Toolchain only supports cluster group of only one type. I.e cluster group of IKS or cluster group of openshift "
            exit 1
        else
            echo "${list[$i]} is an open-shift Cluster. Version:- $VERSION Continue..."
        fi

    done

fi
