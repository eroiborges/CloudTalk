#/bin/bash
if [[ $# < 2 ]];
then
    echo "Missing parameter - required <Resource GroupName>  <Azure Location>"
else

date +"%m/%d/%Y %H:%M:%S $HOSTNAME"

export rgname="$1"
export location="$2"
export myip=$(curl -s -k ifconfig.me)

## Resource Group
az group create --name $rgname --location $location
sleep 5

## NSGs
az network nsg create --resource-group $rgname --name hosts-nsg --location $location
az network nsg rule create --resource-group $rgname --nsg-name hosts-nsg --name ssh-nsg-Rule --protocol tcp --direction inbound --source-address-prefix "$myip" --source-address-prefix "$myip" --source-port-range '*' --destination-address-prefix '*' --destination-port-range 22 --access allow --priority 200

az network nsg create --resource-group $rgname --name pe-nsg --location $location

sleep 5

## VNET for Onpremises Emulation and Subnet AKS
az network vnet create --resource-group $rgname --name lab-vnet --address-prefixes 10.150.0.0/20 --subnet-name hosts --subnet-prefixes 10.150.0.0/26 --location $location --network-security-group hosts-nsg
sleep 5
az network vnet subnet create --address-prefixes 10.150.0.64/26 --name PE --resource-group $rgname --vnet-name lab-vnet --network-security-group pe-nsg
az network vnet subnet create --address-prefixes 10.150.1.0/24 --name pod-aks01 --resource-group $rgname --vnet-name lab-vnet
az network vnet subnet create --address-prefixes 10.150.2.0/24 --name worker-aks01 --resource-group $rgname --vnet-name lab-vnet
az network vnet subnet create --address-prefixes 10.150.3.0/24 --name LB-aks01 --resource-group $rgname --vnet-name lab-vnet

## SubnetIDs
#podaks01sb=$(az network vnet subnet list --resource-group $rgname --vnet-name lab-vnet -o tsv --query "[?name=='pod-aks01'].id")
workeraks01sb=$(az network vnet subnet list --resource-group $rgname --vnet-name lab-vnet -o tsv --query "[?name=='worker-aks01'].id")
#lbaks01sb=$(az network vnet subnet list --resource-group $rgname --vnet-name lab-vnet -o tsv --query "[?name=='LB-aks01'].id")

networkid=$(az network vnet show --resource-group $rgname --name lab-vnet --query "id" -o tsv)
## Remove previus AKS Credential on /tmp directory
rm ./config.temp

## AKSs Cluster
az aks create --resource-group $rgname --name lab-aks-01 --load-balancer-sku standard --node-count 2 --network-plugin azure --network-policy calico --node-osdisk-size 30 --node-vm-size Standard_B2s --os-sku Ubuntu --vnet-subnet-id  $workeraks01sb --dns-service-ip 10.2.0.10 --service-cidr 10.2.0.0/24 --enable-managed-identity
## AKS permission on VNET
sleep 5
aks01identity=$(az aks show --resource-group $rgname --name lab-aks-01 -o tsv --query "identity.principalId")
sleep 5
az role assignment create --role 4d97b98b-1d4f-4787-a291-c67834d212e7 --assignee-object-id $aks01identity --assignee-principal-type ServicePrincipal --scope $networkid
az aks get-credentials --resource-group $rgname --name lab-aks-01 -f ./config.temp


#sleep 5
## NEW FEATURE https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay#set-up-overlay-clusters
#az aks create --resource-group $rgname --name lab-aks-02  --load-balancer-sku standard --node-count 2 --network-plugin azure --network-policy calico --node-osdisk-size 30 --node-vm-size Standard_A2_v2 --os-sku Ubuntu --vnet-subnet-id  $workeraks02sb --network-plugin-mode overlay --pod-cidr 192.168.0.0/16 --docker-bridge-address 172.17.0.1/16 --dns-service-ip 10.2.0.10 --service-cidr 10.2.0.0/24 
## AKS permission on VNET
#sleep 5
#aks02identity=$(az aks show --resource-group $rgname --name lab-aks-02 -o tsv --query "identity.principalId")
#sleep 5
#az role assignment create --role 4d97b98b-1d4f-4787-a291-c67834d212e7 --assignee-object-id $aks02identity --assignee-principal-type ServicePrincipal --scope $networkid
#az aks get-credentials --resource-group $rgname --name lab-aks-02 -f ./config.temp

## NFS FileShare - Storage Account

az storage account create --name eroistornfs --location centralus --resource-group $rgname --account-type Premium_LRS --kind FileStorage --public-network-access Disabled --sku Premium_LRS  
export azstorkey=$(az storage account keys list --account-name eroistornfs --resource-group $rgname -o tsv --query [0].value)
az storage share create --account-name eroistornfs --name nfs01 --account-key $azstorkey


## Admin VM Onpremises
vmsubnet=$(az network vnet subnet list --resource-group $rgname --vnet-name lab-vnet -o tsv --query "[?name=='hosts'].id")
az vm create --name vm-admin --resource-group $rgname --authentication-type ssh --enable-agent false --generate-ssh-keys --image Ubuntu2204 --location $location --size Standard_B2s  --subnet $vmsubnet --public-ip-address "" --nsg "" --query json

### Load Balancer for SSH NAT 
az network lb create --name onpremises-lb --resource-group $rgname --location $location --backend-pool-name bevms --public-ip-address onpremises-pip --frontend-ip-name onpremises-lb--front-ip --sku Basic

export nicname=$(az network nic list -g $rgname -o tsv --query "[?name=='vm-adminVMNic'].name")
export nicipconf=$(az network nic show -n $nicname -g $rgname -o tsv --query ipConfigurations[0].name)
export nicbepool=$(az network lb show -n onpremises-lb -g $rgname -o tsv --query backendAddressPools[].id)

az network nic update --resource-group $rgname --name $nicname --add ipConfigurations[name=$nicipconf].loadBalancerBackendAddressPools id=$nicbepool
az network lb inbound-nat-rule create -g $rgname --lb-name onpremises-lb -n sshNatRule --protocol Tcp --frontend-port 22 --backend-port 22 --frontend-ip-name onpremises-lb--front-ip
az network nic ip-config inbound-nat-rule add -g $rgname --nic-name $nicname -n $nicipconf --lb-name onpremises-lb --inbound-nat-rule sshNatRule

export publicipid=$(az network lb show -g $rgname --name onpremises-lb -o tsv --query frontendIPConfigurations[*].publicIPAddress.id)
export sship=$(az resource show --ids $publicipid -o json --query properties.ipAddress | tr -d \")

sleep 5
scp -o "StrictHostKeyChecking no" ~/.ssh/id_rsa* $sship:~/.ssh/

ssh $USER@$sship "mkdir -p ~/.kube/" && scp -o  "StrictHostKeyChecking no" ./config.temp $sship:~/.kube/config

echo "Finalizado"

echo "SSH para o IP $sship"

date +"%m/%d/%Y %H:%M:%S $HOSTNAME"

fi