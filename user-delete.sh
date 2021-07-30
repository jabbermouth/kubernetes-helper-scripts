#!/bin/bash

username=""
namespaceexec=development
namespaceread=qa,production
kubernetescontrolplane="kubectl.jabbermouth.co.uk"

while getopts ":u:e:r:p:" opt; do
  case $opt in
    u) username="$OPTARG"
    ;;
    e) namespaceexec="$OPTARG"
    ;;
    r) namespaceread="$OPTARG"
    ;;
    p) kubernetescontrolplane="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

echo Removing user context if present
kubectl config delete-context $username-context

echo Removing user if present
kubectl config delete-user $username

echo Removing exec role bindings
IFS=',' read -r -a array <<< "$namespaceexec"
for namespace in "${array[@]}"
do
kubectl delete rolebinding -n $namespace pod-reader-$username
done

echo Removing read only role bindings
IFS=',' read -r -a array <<< "$namespaceread"
for namespace in "${array[@]}"
do
kubectl delete rolebinding -n $namespace pod-readonly-$username
done

echo Deleting sandbox namespace
kubectl delete ns sandbox-$username
