#!/bin/bash

namespace=""
serviceaccountname=tfsbuildagent
kubernetescontrolplane=$(kubectl config view --minify -o jsonpath={.clusters[0].cluster.server})

while getopts ":n:a:?:" opt; do
  case $opt in
    n) namespace="$OPTARG"
    ;;
    a) serviceaccountname="$OPTARG"
    ;;
    ?) 
    echo Options
    echo n = namespace to retrieve secret from
    echo d = name of service account to look up (default: $serviceaccountname)
    exit 0
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ "$namespace" == "" ]; then
echo ERROR: You must specifiy a namespace where service account is located
exit 1
fi

echo
echo Control plane: $kubernetescontrolplane
echo

echo Service Account Secret - copy to ADS
echo
secret=$(kubectl get serviceAccounts $serviceaccountname -n $namespace -o=jsonpath={.secrets[*].name})

kubectl get secret $secret -n $namespace -o json

echo
