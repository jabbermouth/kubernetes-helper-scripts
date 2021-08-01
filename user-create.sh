#!/bin/bash

username=""
dockerhubsecret="dockerhub-jabbermouth"
dockeruser="jabbermouth"
dockerpat=""
configgitrepo="https://Jabbermouth@dev.azure.com/Jabbermouth/Current%20Projects/_git/Jabbermouth.Configuration"
configurationname="common-configuration-values"
valuefiles="common,development,sandbox"
overrideenvironment="development"
confighelmchartreponame="jabbermouth"
confighelmchartrepo="https://helm.jabbermouth.co.uk/"
confighelmchart="Configuration"
company=jabbermouth
namespaceexec=development
namespaceread=qa,production
kubernetescontrolplane=$(kubectl config view --minify -o jsonpath={.clusters[0].cluster.server})
keepusercerts=false

while getopts ":u:c:e:r:h:d:s:a:v:w:x:y:z:o:g:p:k:?:" opt; do
  case $opt in
    u) username="$OPTARG"
    ;;
    c) company="$OPTARG"
    ;;
    e) namespaceexec="$OPTARG"
    ;;
    r) namespaceread="$OPTARG"
    ;;
    h) dockeruser="$OPTARG"
    ;;
    d) dockerpat="$OPTARG"
    ;;
    s) dockerhubsecret="$OPTARG"
    ;;
    a) configgitrepo=${configgitrepo/@/:$OPTARG@}
    ;;
    g) configgitrepo="$OPTARG"
    ;;
    w) configurationname="$OPTARG"
    ;;
    x) confighelmchartreponame="$OPTARG"
    ;;
    y) confighelmchartrepo="$OPTARG"
    ;;
    z) confighelmchart="$OPTARG"
    ;;
    v) valuefiles="$OPTARG"
    ;;
    o) overrideenvironment="$OPTARG"
    ;;
    p) kubernetescontrolplane="$OPTARG"
    ;;
    k) keepusercerts=($OPTARG="true")
    ;;
    ?) 
    echo "Usage: helpers/user-create.sh [OPTIONS]"
    echo
    echo "Options"
    echo "u = user name (in the format first-name) of account to create"
    echo "c = name of company used in generated certificate (default: $company)"
    echo "e = namespaces to grant user exec rights to (default: $namespaceexec)"
    echo "r = namespaces to grant user readonly (e.g. list pods, see logs) rights to (default: $namespaceread)"
    echo "h = name of Docker Hub user (default: $dockeruser)"
    echo "d = Docker Hub PAT to use for connecting - if blank (default) then no secret will be created"
    echo "s = name of secret used to store Docker Hub credentials (default: $dockerhubsecret)"
    echo "a = Azure DevOps Services PAT to use for populating standard CABI configuration"
    echo "g = Specifies the a Git repo which contains a configuration repo to apply (default: $configgitrepo)"
    echo "w = name of the release created for common configuration values (default: $configurationname)"
    echo "x = name to give the Helm chart repo (default: $confighelmchartreponame)"
    echo "y = URL of the Helm chart repo (default: $confighelmchartrepo)"
    echo "z = name of the configuration Helm chart to install (default: $confighelmchart)"
    echo "v = a comma-delimited list of configuration files to import in the order the should be imported (default: $valuefiles)"
    echo "o = the environment that should be used instead of the default (default: $overrideenvironment)"
    echo "k = if true, user certificates are added to the local configuration to allow use on this machine (default: $keepusercerts)"
    echo "p = Protocol, IP/name and port of Kubernetes control plane (default: $kubernetescontrolplane)"
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

if [ "$dockerpat" == "" ]; then
echo ERROR: You must specifiy a Docker Hub PAT
exit 2
fi

echo generating certificate

sudo openssl genrsa -out user-$username.key 2048
sudo openssl req -new -key user-$username.key -out user-$username.csr -subj "/CN=$username/O=$company"
sudo openssl x509 -req -in user-$username.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out user-$username.crt -days 500

echo removing temporary certificate

rm -f user-$username.csr

echo storing values in variables

cacrt=$(sudo cat /etc/kubernetes/pki/ca.crt | base64 | tr -d '\n')
crt=$(cat user-$username.crt | base64 | tr -d '\n')
key=$(sudo cat user-$username.key | base64 | tr -d '\n')

echo remove any existing user

rm -f user-$username.config

echo generate user

cat <<EOM >user-$username.config
apiVersion: v1
kind: Config
users:
- name: $username
  user:
    client-certificate-data: $crt
    client-key-data: $key
clusters:
- cluster:
    certificate-authority-data: $cacrt
    server: $kubernetescontrolplane
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    namespace: sandbox-$username
    user: $username
  name: $username-context@kubernetes
current-context: $username-context@kubernetes
EOM


if [ keepusercerts == true ]; then
echo storing certificate to allow context use

kubectl config set-credentials $username --client-certificate=user-$username.crt  --client-key=user-$username.key

IFS=',' read -r -a array <<< "$namespaceexec"
for namespace in "${array[@]}"
do
kubectl config set-context $username-context --cluster=kubernetes --namespace=$namespace --user=$username
done

IFS=',' read -r -a array <<< "$namespaceread"
for namespace in "${array[@]}"
do
kubectl config set-context $username-context --cluster=kubernetes --namespace=$namespace --user=$username
done

else
echo discarding certificates

rm -f user-$username.crt
rm -f user-$username.key
fi

echo creating sandbox

kubectl create ns sandbox-$username

if [ "$dockerpat" != "" ]; then
echo Docker Hub PAT specified so adding Docker Hub secret to allow repo access

kubectl delete secret $dockerhubsecret -n sandbox-$username

kubectl create secret docker-registry $dockerhubsecret --docker-username=$dockeruser --docker-password=$dockerpat --docker-email= --namespace sandbox-$username
fi

if [ "$configgitrepo" != "" ]; then

echo fetching config from Git

rm -R -f preinstalled-config
git clone $configgitrepo preinstalled-config

echo setting up config files using Helm chart

helm repo add $confighelmchartreponame $confighelmchartrepo
helm repo update

values=""
IFS=',' read -r -a array <<< "$valuefiles"
for valuefile in "${array[@]}"
do
values="$values -f preinstalled-config/$valuefile.yaml"
done

helm upgrade --namespace sandbox-$username --install $values --set cabiUrls.overrideNamespace=$overrideNamespace $configurationname $confighelmchartreponame/$confighelmchart

echo removing configuration files from local disk
rm -R -f preinstalled-config

fi

echo generate roles and add role bindings

cat <<EOM >user-$username.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: sandbox-$username
  name: sandbox-admin
rules:
- apiGroups: ["", "networking.k8s.io", "extensions", "apps", "autoscaling", "cert-manager.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs: ["*"]
---

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sandbox-owner
  namespace: sandbox-$username
subjects:
- kind: User
  name: $username
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: sandbox-admin
  apiGroup: rbac.authorization.k8s.io
EOM

echo apply roles for sandbox

kubectl apply -f user-$username.yaml

echo removing creation yaml

rm user-$username.yaml

IFS=',' read -r -a array <<< "$namespaceexec"
for namespace in "${array[@]}"
do
echo adding role and binding for $namespace

cat <<EOM >user-$username-$namespace.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $namespace
  name: pod-reader
rules:
- apiGroups: ["extensions", "apps","networking.k8s.io", "extensions", "apps", "autoscaling", "cert-manager.io"]
  resources: ["deployments","ingresses","daemonsets","replicasets","horizontalpodautoscalers","statefulsets","certificates","certificaterequests"]
  verbs: ["get", "watch", "list"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods","pods/log","services","configmaps","replicationcontrollers","persistentvolumeclaims","endpoints","events"]
  verbs: ["get", "watch", "list", "exec","describe"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets"]
  verbs: ["list"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs: ["get","watch","list"]
---

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-$username
  namespace: $namespace
subjects:
- kind: User
  name: $username
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io

---

EOM

echo apply roles for $namespace

kubectl apply -f user-$username-$namespace.yaml

echo removing creation yaml

rm user-$username-$namespace.yaml

done

echo
echo Copy this file into a config file name $username.config and place in a folder on your machine called c:\k8s
echo

cat user-$username.config

echo
