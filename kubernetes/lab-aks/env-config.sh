#/bin/bash

if [[ $# < 2 ]];
then
    echo "Missing parameter "
else
#    for i in $@
#      do
#        echo -e "$i\n"
#      done


resourcegroupname="$1"
datacenter="$2"
export myip=$(curl -k ifconfig.me)


## Resource Group
az group create --name $resourcegroupname --location $datacenter

## NSG for CKA VMs
az network nsg create --resource-group $resourcegroupname --name kube-nsg --location $datacenter
az network nsg rule create --resource-group $resourcegroupname --nsg-name kube-nsg --name kube-nsg-Rule --protocol tcp --direction inbound --source-address-prefix "$myip" --source-port-range '*' --destination-address-prefix '*' --destination-port-range 22 --access allow --priority 200

## VNET for Both + Subnet AKS
az network vnet create --resource-group $resourcegroupname --name aks-vnet --address-prefixes 10.150.0.0/24 --subnet-name cluster-aks --subnet-prefixes 10.150.0.0/25 --location $datacenter

## Subnet for CKA
az network vnet subnet create --address-prefixes 10.150.0.128/25 --name cluster-cka --resource-group $resourcegroupname --vnet-name aks-vnet --network-security-group kube-nsg

echo "###########################################"
echo "## SEU IP INTERNET: $myip "
echo "###########################################"

fi
