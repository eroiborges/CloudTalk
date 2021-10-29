#/bin/bash

if [[ $# < 6 ]];
then
    echo "Missing parameter "
else
#    for i in $@
#      do
#        echo -e "$i\n"
#      done

export aksrg="$1"
clustername=$2
datacenter="$3"
vnetrg="$4"
kubeversion="$5"
nodes=$6

## Get VNET/SUBNET
export subnetid=$(az network vnet show -n aks-vnet -g $vnetrg --query "subnets[0].id" --output tsv)

## Create RG for AKS
az group create --name $aksrg --location $datacenter

## Create AKS
az aks create -g $aksrg -n $clustername -l $datacenter --kubernetes-version $kubeversion --node-count $nodes --generate-ssh-keys --enable-managed-identity --load-balancer-sku basic --network-plugin azure --vnet-subnet-id $subnetid --network-policy calico --node-osdisk-size 30 --node-vm-size Standard_A2_v2 --os-sku Ubuntu --service-cidr 10.160.0.0/24 --dns-service-ip 10.160.0.10 --no-wait -y

## Export Config file
az aks get-credentials --resource-group $aksrg --name $clustername

fi
