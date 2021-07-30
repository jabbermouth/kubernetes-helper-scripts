#!/bin/bash

dockerhubsecret="dockerhub-jabbermouth"
dockeruser="jabbermouth"
dockerpat=""
namespaces=development,qa,production
serviceaccountname=tfsbuildagent

while getopts ":n:h:d:s:a:?:" opt; do
  case $opt in
    n) namespaces="$OPTARG"
    ;;
    d) dockeruser="$OPTARG"
    ;;
    p) dockerpat="$OPTARG"
    ;;
    s) dockerhubsecret="$OPTARG"
    ;;
    a) serviceaccountname="$OPTARG"
    ;;
    ?) 
    echo "Usage: helpers/build-service-account-create.sh [OPTIONS]"
    echo
    echo "Options"
    echo "n = namespaces to create build agent accounts in (default: $namespaces)"
    echo "d = name of Docker Hub user (default: $dockeruser)"
    echo "p = Docker Hub PAT to use for connecting - if blank (default) then no secret will be created"
    echo "s = name of secret used to store Docker Hub credentials (default: $dockerhubsecret)"
    echo "a = name of service account to create (default: $serviceaccountname)"
    exit 0
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

echo generated cluster role

cat <<EOM >buildagent-clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: api-access
rules:
  -
    apiGroups:
      - ""
      - apps
      - autoscaling
      - batch
      - cert-manager.io
      - extensions
      - networking.k8s.io
      - policy
      - rbac.authorization.k8s.io
      - clusterroles.rbac.authorization.k8s.io
    resources:
      - clusterissuers
      - componentstatuses
      - configmaps
      - daemonsets
      - deployments
      - events
      - endpoints
      - horizontalpodautoscalers
      - ingresses
      - jobs
      - limitranges
      - namespaces
      - nodes
      - pods
      - persistentvolumes
      - persistentvolumeclaims
      - resourcequotas
      - replicasets
      - replicationcontrollers
      - secrets
      - serviceaccounts
      - services
    verbs: ["*"]
  - nonResourceURLs: ["*"]
    verbs: ["*"]
EOM

echo apply role

kubectl apply -f buildagent-clusterrole.yaml

echo removing creation yaml

rm buildagent-clusterrole.yaml

echo generate role binding
cat <<EOM >buildagent-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: api-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: api-access
subjects:
EOM

IFS=',' read -r -a array <<< "$namespaces"
for namespace in "${array[@]}"
do

if [ "$dockerpat" != "" ]; then
echo Docker Hub PAT specified so adding Docker Hub secret to allow repo access

kubectl delete secret $dockerhubsecret -n $namespace

kubectl create secret docker-registry $dockerhubsecret --docker-username=$dockeruser --docker-password=$dockerpat --docker-email= --namespace $namespace
fi

echo generate service account

cat <<EOM >buildagent-serviceaccount-$namespace.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $serviceaccountname
  namespace: $namespace
imagePullSecrets:
- name: $dockerhubsecret
EOM

echo apply service account for $namespace

kubectl apply -f buildagent-serviceaccount-$namespace.yaml

echo remove service account definition for $namespace

rm -f buildagent-serviceaccount-$namespace.yaml

echo add service account to cluster role binding
cat <<EOM >>buildagent-rolebinding.yaml
- kind: ServiceAccount
  name: $serviceaccountname
  namespace: $namespace
EOM

done

echo apply cluster role binding
kubectl apply -f buildagent-rolebinding.yaml

echo remove cluster role binding YAML file
rm buildagent-rolebinding.yaml

echo
echo All bindings and users have been configured
echo
