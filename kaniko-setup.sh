#!/bin/bash

namespace=build-agents
dockersecret=dockerhub-jabbermouth

while getopts ":n:d:?:" opt; do
  case $opt in
    n) namespace="$OPTARG"
    ;;
    d) dockersecret="$OPTARG"
    ;;
    ?) 
    echo "Usage: helpers/kaniko-setup.sh [OPTIONS]"
    echo
    echo "Options"
    echo "n = namespace to create kaniko account in (default: $namespace)"
    echo "d = name of Docker Hub secret to use (default: $dockersecret)"
    exit 0
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

echo
echo Removing existing file if present
rm kaniko-user.yaml

echo
echo Generating new user creating manifests
cat <<EOM >kaniko-user.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-runner
rules:
  -
    apiGroups:
      - ""
      - apps
    resources:
      - pods
    verbs: ["get", "watch", "list", "create", "delete", "update", "patch"]

---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: kaniko
  namespace: $namespace
imagePullSecrets:
- name: $dockersecret

---

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kaniko-pod-runner
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pod-runner
subjects:
- kind: ServiceAccount
  name: kaniko
  namespace: $namespace
EOM

echo
echo Applying user manifests
kubectl apply -f kaniko-user.yaml

echo
echo Tidying up manifests
rm kaniko-user.yaml

echo
echo Getting secret
echo
secret=$(kubectl get serviceAccounts kaniko -n $namespace -o=jsonpath={.secrets[*].name})

token=$(kubectl get secret $secret -n $namespace -o=jsonpath={.data.token})

echo Or paste the following token where needed:
echo
echo $token | base64 --decode
echo
