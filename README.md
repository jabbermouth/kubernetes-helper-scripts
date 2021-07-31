# kubernetes-helper-scripts
A collection of scripts to help when setting up Kubernetes.  They are slanted for use in my private cluster but could be easily adapted.
To install the scripts from Ubuntu, run the following command:
```
sudo apt update && sudo apt install -y git && rm -R -f helpers && git clone https://github.com/jabbermouth/kubernetes-helper-scripts.git helpers && bash helpers/setup-helper-scripts.sh
```

Once installed, you can run the following command to update the scripts:
```
helpers/refresh.sh
```

To get details of all parameters, you can use -?.  For example:
```
helpers/user-create.sh -?
```