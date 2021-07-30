#!/bin/bash

username=""
namespaceexec=development
namespaceread=qa,production

while getopts ":u:e:r:?:" opt; do
  case $opt in
    u) username="$OPTARG"
    ;;
    e) namespaceexec="$OPTARG"
    ;;
    r) namespaceread="$OPTARG"
    ;;
    ?) 
    echo Options
    echo u = user name (in the format first-name) of account to delete
    echo e = exec capable namespaces (comma delimited) of all exec-enabled namespaces (default: $namespaceexec)
    echo r = readonly namespaces (comma delimited) of all readonly namespaces (default: $namespaceread)
    exit 0
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ "$username" == "" ]; then
echo ERROR: You must specifiy a user name in the format first-name
exit 1
fi

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
