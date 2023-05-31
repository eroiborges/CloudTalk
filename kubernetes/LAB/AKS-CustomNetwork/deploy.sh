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
az network nsg create --resource-group $rgname --name onpremises-nsg --location $location
az network nsg rule create --resource-group $rgname --nsg-name onpremises-nsg --name ssh-nsg-Rule --protocol tcp --direction inbound --source-address-prefix "$myip" --source-address-prefix "$myip" --source-port-range '*' --destination-address-prefix '*' --destination-port-range 22 --access allow --priority 200
sleep 5

## VNET for Onpremises Emulation and Subnet AKS
az network vnet create --resource-group $rgname --name onpremises-vnet --address-prefixes 10.0.0.0/22 --subnet-name hosts --subnet-prefixes 10.0.0.0/24 --location $location --network-security-group onpremises-nsg
sleep 5
az network vnet create --resource-group $rgname --name kubernetes-vnet --address-prefixes 10.150.0.0/20 --subnet-name hosts --subnet-prefixes 10.150.0.0/26 --location $location
sleep 5
az network vnet subnet create --address-prefixes 10.150.0.64/26 --name AzureFirewallSubnet --resource-group $rgname --vnet-name kubernetes-vnet
az network vnet subnet create --address-prefixes 10.150.0.128/26 --name AzureFirewallManagementSubnet --resource-group $rgname --vnet-name kubernetes-vnet
az network vnet subnet create --address-prefixes 10.150.1.0/24 --name pod-aks01 --resource-group $rgname --vnet-name kubernetes-vnet
az network vnet subnet create --address-prefixes 10.150.2.0/24 --name worker-aks01 --resource-group $rgname --vnet-name kubernetes-vnet
az network vnet subnet create --address-prefixes 10.150.3.0/24 --name LB-aks01 --resource-group $rgname --vnet-name kubernetes-vnet
az network vnet subnet create --address-prefixes 10.150.4.0/24 --name worker-aks02 --resource-group $rgname --vnet-name kubernetes-vnet
az network vnet subnet create --address-prefixes 10.150.5.0/24 --name LB-aks02 --resource-group $rgname --vnet-name kubernetes-vnet

## Peering VNETs
vNet1Id=$(az network vnet show --resource-group $rgname --name onpremises-vnet --query id --out tsv)
vNet2Id=$(az network vnet show --resource-group $rgname --name kubernetes-vnet --query id --out tsv)

az network vnet peering create --name vnet1-2-vnet2 --resource-group $rgname --vnet-name onpremises-vnet --remote-vnet $vNet2Id --allow-vnet-access
az network vnet peering create --name vnet2-2-vnet1 --resource-group $rgname --vnet-name kubernetes-vnet --remote-vnet $vNet1Id --allow-vnet-access
sleep 5

## SubnetIDs
podaks01sb=$(az network vnet subnet list --resource-group $rgname --vnet-name kubernetes-vnet -o tsv --query "[?name=='pod-aks01'].id")
workeraks01sb=$(az network vnet subnet list --resource-group $rgname --vnet-name kubernetes-vnet -o tsv --query "[?name=='worker-aks01'].id")
lbaks01sb=$(az network vnet subnet list --resource-group $rgname --vnet-name kubernetes-vnet -o tsv --query "[?name=='LB-aks01'].id")
workeraks02sb=$(az network vnet subnet list --resource-group $rgname --vnet-name kubernetes-vnet -o tsv --query "[?name=='worker-aks02'].id")
lbaks02sb=$(az network vnet subnet list --resource-group $rgname --vnet-name kubernetes-vnet -o tsv --query "[?name=='LB-aks02'].id")

## Az Firewall

### Az Policy
az extension add --name azure-firewall -y
sleep 5

az network firewall policy create --name fw-lab-policy --resource-group $rgname --sku Basic
sleep 5

az network firewall policy rule-collection-group create --name onpremises-rules --policy-name fw-lab-policy --priority 200 --resource-group $rgname
az network firewall policy rule-collection-group collection add-filter-collection -g $rgname --policy-name fw-lab-policy --rule-collection-group-name onpremises-rules --name aks-mgmt --action Allow --rule-name AKS-API --rule-type NetworkRule --description "management of aks cluster" --destination-addresses "10.150.2.0/24" "10.150.4.0/24" --source-addresses "10.0.0.0/24" --destination-ports 443 --ip-protocols TCP --collection-priority 100
sleep 5

## Internet Full opened only for lab propose 
az network firewall policy rule-collection-group create --name DefaultNetworkRuleCollectionGroup --policy-name fw-lab-policy --priority 100 --resource-group $rgname
#az network firewall policy rule-collection-group collection add-filter-collection -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultNetworkRuleCollectionGroup --name Internet-out --action Allow --rule-name HTTP --rule-type NetworkRule --description "Allow HTTP" --destination-addresses "*" --source-addresses "*" --destination-ports "80" "443" --ip-protocols "TCP" "UDP" --collection-priority 100
#az network firewall policy rule-collection-group collection add-filter-collection -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultNetworkRuleCollectionGroup --name aks-api-udp --action Allow --rule-name apiudp --rule-type NetworkRule --description "Allow UDP 1194" --destination-addresses "AzureCloud.$location" --source-addresses "*" --destination-ports "1194" --ip-protocols "UDP" --collection-priority 101
#az network firewall policy rule-collection-group collection add-filter-collection -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultNetworkRuleCollectionGroup --name aks-api-tcp --action Allow --rule-name apitcp --rule-type NetworkRule --description "Allow TCP 9000" --destination-addresses "AzureCloud.$location" --source-addresses "*" --destination-ports "9000" --ip-protocols "TCP" --collection-priority 102
az network firewall policy rule-collection-group collection add-filter-collection -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultNetworkRuleCollectionGroup --name aks-ntp --action Allow --rule-name ntp --rule-type NetworkRule --description "Allow NTP" --destination-addresses "*" --source-addresses "*" --destination-ports "123" --ip-protocols "UDP" --collection-priority 103
sleep 5
az network firewall policy rule-collection-group create --name DefaultApplicationRuleCollectionGroup --policy-name fw-lab-policy --priority 100 --resource-group $rgname
az network firewall policy rule-collection-group collection add-filter-collection -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --name AzureGlobal --action Allow --rule-name location --rule-type ApplicationRule --description "AKS HTTP URL" --target-fqdns "*.hcp.$location.azmk8s.io" --source-addresses "*" --destination-ports "443" --protocols http=80 https=443 --collection-priority 100
az network firewall policy rule-collection-group collection rule add -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --collection-name AzureGlobal --name mcr      --rule-type ApplicationRule --description "AKS HTTP URL" --target-fqdns "mcr.microsoft.com"         --source-addresses "*" --destination-ports "443" --protocols https=443
az network firewall policy rule-collection-group collection rule add -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --collection-name AzureGlobal --name mcr2     --rule-type ApplicationRule --description "AKS HTTP URL" --target-fqdns "*.data.mcr.microsoft.com"  --source-addresses "*" --destination-ports "443" --protocols https=443 
az network firewall policy rule-collection-group collection rule add -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --collection-name AzureGlobal --name mgmt     --rule-type ApplicationRule --description "AKS HTTP URL" --target-fqdns "management.azure.com"      --source-addresses "*" --destination-ports "443" --protocols https=443 
az network firewall policy rule-collection-group collection rule add -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --collection-name AzureGlobal --name login    --rule-type ApplicationRule --description "AKS HTTP URL" --target-fqdns "login.microsoftonline.com" --source-addresses "*" --destination-ports "443" --protocols https=443
az network firewall policy rule-collection-group collection rule add -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --collection-name AzureGlobal --name packages --rule-type ApplicationRule --description "AKS HTTP URL" --target-fqdns "packages.microsoft.com"    --source-addresses "*" --destination-ports "443" --protocols https=443
az network firewall policy rule-collection-group collection rule add -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --collection-name AzureGlobal --name acs      --rule-type ApplicationRule --description "AKS HTTP URL" --target-fqdns "acs-mirror.azureedge.net"  --source-addresses "*" --destination-ports "443" --protocols https=443
sleep 5
az network firewall policy rule-collection-group collection add-filter-collection -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --name helm --action Allow --rule-name image --rule-type ApplicationRule --description "HELM image HTTP URL" --target-fqdns "*" --source-addresses "10.150.2.0/24" "10.150.4.0/24" --destination-ports "80" "443" --protocols http=80 https=443 --collection-priority 101
az network firewall policy rule-collection-group collection rule add -g $rgname --policy-name fw-lab-policy --rule-collection-group-name DefaultApplicationRuleCollectionGroup --collection-name helm --name docker --rule-type ApplicationRule --description "Helm image HTTP URL" --target-fqdns "*.docker.io" "*.cloudfront.net" "*.docker.com" --source-addresses "*" --destination-ports "80" "443" --protocols http=80 https=443

sleep 5

az network public-ip create -g $rgname -n fw-lab-pip --sku Standard --allocation-method static --sku standard
az network public-ip create -g $rgname -n fw-lab-m-pip --sku Standard --allocation-method static --sku standard
sleep 5
az network firewall create -g $rgname --location $location -n fw-lab --sku AZFW_VNet --tier Basic --vnet-name kubernetes-vnet --conf-name fw-labIpConfig --m-conf-name ManagementIpConfig --public-ip fw-lab-pip --m-public-ip fw-lab-m-pip --firewall-policy fw-lab-policy 

## UDRs

fwprivip=$(az network firewall show -g $rgname -n fw-lab -o tsv --query ipConfigurations[0].privateIPAddress)

az network route-table create --name onpremises-route --resource-group $rgname --location $location --disable-bgp-route-propagation false
az network route-table create --name kubernets-route --resource-group $rgname --location $location --disable-bgp-route-propagation false

az network vnet subnet update --name hosts --vnet-name onpremises-vnet -g $rgname --route-table onpremises-route
sleep 5
az network vnet subnet update --name worker-aks01 --vnet-name kubernetes-vnet -g $rgname --route-table kubernets-route
sleep 5
az network vnet subnet update --name pod-aks01 --vnet-name kubernetes-vnet -g $rgname --route-table kubernets-route
sleep 5
az network vnet subnet update --name worker-aks02 --vnet-name kubernetes-vnet -g $rgname --route-table kubernets-route
sleep 5


#10.0.0.0/22
#10.150.0.0/20
az network route-table route create --name Onpremises-2-kubernetes --resource-group $rgname --route-table-name onpremises-route --address-prefix "10.150.0.0/20"  --next-hop-ip-address $fwprivip --next-hop-type VirtualAppliance 
sleep 5
az network route-table route create --name to-internet --resource-group $rgname --route-table-name kubernets-route --address-prefix "0.0.0.0/0"  --next-hop-ip-address $fwprivip --next-hop-type VirtualAppliance 
az network route-table route create --name kubernetes-2-onpremises --resource-group $rgname --route-table-name kubernets-route --address-prefix "10.0.0.0/22"  --next-hop-ip-address $fwprivip --next-hop-type VirtualAppliance 


networkid=$(az network vnet show --resource-group $rgname --name kubernetes-vnet --query "id" -o tsv)
onprenetworkid=$(az network vnet show --resource-group $rgname --name onpremises-vnet --query "id" -o tsv)

## Remove previus AKS Credential on /tmp directory

rm ./config.temp

## AKSs Cluster
az aks create --resource-group $rgname --name lab-aks-01 --enable-private-cluster --load-balancer-sku standard --node-count 2 --network-plugin azure --network-policy calico --node-osdisk-size 30 --node-vm-size Standard_A2_v2 --os-sku Ubuntu --vnet-subnet-id  $workeraks01sb --pod-subnet-id $podaks01sb --docker-bridge-address 172.17.0.1/16 --dns-service-ip 10.2.0.10 --service-cidr 10.2.0.0/24 --outbound-type userDefinedRouting
## AKS permission on VNET
sleep 5
aks01identity=$(az aks show --resource-group $rgname --name lab-aks-01 -o tsv --query "identity.principalId")
sleep 5
az role assignment create --role 4d97b98b-1d4f-4787-a291-c67834d212e7 --assignee-object-id $aks01identity --assignee-principal-type ServicePrincipal --scope $networkid
## DNS Private Zone link
aks01RG=$(az aks show --resource-group $rgname --name lab-aks-01 -o tsv --query nodeResourceGroup)
aks01zonename=$(az network private-dns zone list -g $aks01RG -o tsv --query [].name)
sleep 5
az network private-dns link vnet create -n aks-onpremises -g $aks01RG  -z $aks01zonename -v $onprenetworkid -e false
az aks get-credentials --resource-group $rgname --name lab-aks-01 -f ./config.temp


sleep 5
## NEW FEATURE https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay#set-up-overlay-clusters
az aks create --resource-group $rgname --name lab-aks-02 --enable-private-cluster --load-balancer-sku standard --node-count 2 --network-plugin azure --network-policy calico --node-osdisk-size 30 --node-vm-size Standard_A2_v2 --os-sku Ubuntu --vnet-subnet-id  $workeraks02sb --network-plugin-mode overlay --pod-cidr 192.168.0.0/16 --docker-bridge-address 172.17.0.1/16 --dns-service-ip 10.2.0.10 --service-cidr 10.2.0.0/24 --outbound-type userDefinedRouting
## AKS permission on VNET
sleep 5
aks02identity=$(az aks show --resource-group $rgname --name lab-aks-02 -o tsv --query "identity.principalId")
sleep 5
az role assignment create --role 4d97b98b-1d4f-4787-a291-c67834d212e7 --assignee-object-id $aks02identity --assignee-principal-type ServicePrincipal --scope $networkid
## DNS Private Zone link
aks02RG=$(az aks show --resource-group $rgname --name lab-aks-02 -o tsv --query nodeResourceGroup)
aks02zonename=$(az network private-dns zone list -g $aks02RG -o tsv --query [].name)
sleep 5
az network private-dns link vnet create -n aks-onpremises -g $aks02RG  -z $aks02zonename -v $onprenetworkid -e false
az aks get-credentials --resource-group $rgname --name lab-aks-02 -f ./config.temp

## Admin VM Onpremises
vmsubnet=$(az network vnet subnet list --resource-group $rgname --vnet-name onpremises-vnet -o tsv --query "[?name=='hosts'].id")
az vm create --name vm-admin --resource-group $rgname --authentication-type ssh --enable-agent false --generate-ssh-keys --image Ubuntu2204 --location $location --size Standard_B2s  --subnet $vmsubnet --public-ip-address "" --nsg "" --query json


sleep 5
## Admin VM Kubernetes
vmsubnet2=$(az network vnet subnet list --resource-group $rgname --vnet-name kubernetes-vnet -o tsv --query "[?name=='worker-aks01'].id")
az vm create --name vm-admin2 --resource-group $rgname --authentication-type ssh --enable-agent false --generate-ssh-keys --image Ubuntu2204 --location $location --size Standard_B2s  --subnet $vmsubnet2 --public-ip-address "" --nsg "" --query json


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
ssh $USER@$sship "mkdir -p ~/yaml/" && scp -rp  ./yaml $sship:~/yaml

echo "Finalizado"

echo "SSH para o IP $sship"

date +"%m/%d/%Y %H:%M:%S $HOSTNAME"

fi