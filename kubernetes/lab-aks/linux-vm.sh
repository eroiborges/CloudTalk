#/bin/bash

if [[ $# < 5 ]];
then
    echo "Missing parameter "
else
#    for i in $@
#      do
#        echo -e "$i\n"
#      done

vmrg="$1"
clustername="$2"
datacenter="$3"
vnetrg="$4"
nodes=$5
export subnetid=$(az network vnet show -n aks-vnet -g $vnetrg --query "subnets[1].id" --output tsv)

## RG
az group create --name $vmrg --location $datacenter

## VMs
az vm create --name $clustername --resource-group $vmrg --authentication-type ssh --count $nodes --enable-agent false --generate-ssh-keys --image UbuntuLTS --location $datacenter --size Standard_A2_v2  --vnet-name aks-vnet  --subnet cluster-cka --public-ip-address "" --nsg "" --query json

## LB
az network lb create --name kube-lb --resource-group $vmrg --location $datacenter --backend-pool-name Kubevms --public-ip-address kube-ip --frontend-ip-name kube-lb-ip --sku Basic

export nicname=$(az network nic list -g $vmrg -o tsv --query [0].name)
export nicipconf=$(az network nic list -g $vmrg -o tsv --query [0].ipConfigurations[0].name)
export nicbepool=$(az network lb show -n kube-lb -g $vmrg -o tsv --query backendAddressPools[].id)

az network nic update --resource-group $vmrg --name $nicname --add ipConfigurations[name=$nicipconf].loadBalancerBackendAddressPools id=$nicbepool

az network lb inbound-nat-rule create -g $vmrg --lb-name kube-lb -n kubeNatRule --protocol Tcp --frontend-port 22 --backend-port 22 --frontend-ip-name kube-lb-ip 

az network nic ip-config inbound-nat-rule add -g $vmrg --nic-name $nicname -n $nicipconf --lb-name kube-lb --inbound-nat-rule kubeNatRule

export publicipid=$(az network lb show -g $vmrg --name kube-lb -o tsv --query frontendIpConfigurations[].publicIpAddress.id)
export sship=$(az resource show --ids $publicipid -o json --query properties.ipAddress | tr -d \")

echo -n "SSH para o IP $sship"

ssh $sship -o "StrictHostKeyChecking no"
fi
