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


## NSGs
az network nsg create --resource-group $rgname --name onpremises-nsg --location $location
az network nsg rule create --resource-group $rgname --nsg-name onpremises-nsg --name ssh-nsg-Rule --protocol tcp --direction inbound --source-address-prefix "$myip" --source-address-prefix "$myip" --source-port-range '*' --destination-address-prefix '*' --destination-port-range 22 --access allow --priority 200
sleep 5

## VNET for Onpremises Emulation and Subnet AKS
az network vnet create --resource-group $rgname --name onpremises-vnet --address-prefixes 10.0.0.0/22 --subnet-name hosts --subnet-prefixes 10.0.0.0/26 --location $location --network-security-group onpremises-nsg
az network vnet subnet create --address-prefixes 10.0.0.64/26 --name GatewaySubnet --resource-group $rgname --vnet-name onpremises-vnet
sleep 5
az network vnet create --resource-group $rgname --name azure-vnet --address-prefixes 10.150.0.0/20 --subnet-name hosts --subnet-prefixes 10.150.0.0/26 --location $location
sleep 5
az network vnet subnet create --address-prefixes 10.150.0.64/26 --name GatewaySubnet --resource-group $rgname --vnet-name azure-vnet
az network vnet subnet create --address-prefixes 10.150.0.128/26 --name AzureFirewallSubnet --resource-group $rgname --vnet-name azure-vnet
az network vnet subnet create --address-prefixes 10.150.0.192/26 --name AzureFirewallManagementSubnet --resource-group $rgname --vnet-name azure-vnet

# VM Public IP
az network public-ip create -g $rgname -n onpremises-vpn-pip --sku Standard --allocation-method static --sku standard
export vmpublicpip=$(az network public-ip show -g $rgname -n onpremises-vpn-pip -o tsv --query ipAddress)

## VNET Gateway
az network public-ip create -g $rgname -n vpn-gw-pip --sku Standard --allocation-method static --sku standard
az network local-gateway create --gateway-ip-address $vmpublicpip --name mysite --resource-group $rgname --local-address-prefixes 10.0.0.0/22
az network vnet-gateway create --name vnet-vpngw --resource-group $rgname --vnet azure-vnet --gateway-default-site mysite --gateway-type Vpn --location $location --no-wait true --public-ip-address vpn-gw-pip --sku VpnGw1 --vpn-gateway-generation Generation1 --vpn-type RouteBased


## VM VPN Onpremises
export prState=''
while [[ $prState != 'Succeeded' ]];
do
    prState=$(az network public-ip show -g $rgname -n onpremises-vpn-pip -o tsv --query provisioningState)
    echo "Public IP provisioningState="$prState
    sleep 5
done


vmsubnet=$(az network vnet subnet list --resource-group $rgname --vnet-name onpremises-vnet -o tsv --query "[?name=='hosts'].id")
az vm create --name vm-vpn --resource-group $rgname --authentication-type ssh --enable-agent false --generate-ssh-keys --image Ubuntu2204 --location $location --size Standard_B2s  --subnet $vmsubnet --public-ip-address "onpremises-vpn-pip" --nsg "" --query json --no-wait

export prState=''
while [[ $prState != 'Succeeded' ]];
do
    prState=$(az vm show --name vm-admin --resource-group $rgname -o tsv --query provisioningState)
    echo "VM  provisioningState="$prState
    sleep 5
done
scp -o "StrictHostKeyChecking no" ~/.ssh/id_rsa* $vmpublicpip:~/.ssh/

## VM backend
vmsubnet=$(az network vnet subnet list --resource-group $rgname --vnet-name azure-vnet -o tsv --query "[?name=='hosts'].id")
az vm create --name vm-backend --resource-group $rgname --authentication-type ssh --enable-agent false --generate-ssh-keys --image Ubuntu2204 --location $location --size Standard_B2s  --subnet $vmsubnet --public-ip-address "" --nsg "" --query json --no-wait

## VM Onpremises backend
vmsubnet=$(az network vnet subnet list --resource-group $rgname --vnet-name onpremises-vnet -o tsv --query "[?name=='hosts'].id")
az vm create --name vm-onp-backend --resource-group $rgname --authentication-type ssh --enable-agent false --generate-ssh-keys --image Ubuntu2204 --location $location --size Standard_B2s  --subnet $vmsubnet --public-ip-address "" --nsg "" --query json --no-wait


## VPN Connect VPN Gateway with LocalNetworkGateway
export prState=''
while [[ $prState != 'Succeeded' ]];
do
    prState=$(az network vnet-gateway show --name vnet-vpngw --resource-group $rgname -o tsv --query provisioningState)
    echo "VPN Gateway provisioningState="$prState
    sleep 5
done
az network vpn-connection create --name VNet1toSite2 --resource-group $rgname --vnet-gateway1 vnet-vpngw -l $location --shared-key b2xAbXVuZDBjcnVlbA== --local-gateway2 mysite


echo "IP de Conexão:" $(az network public-ip show -g $rgname -n onpremises-vpn-pip -o tsv --query ipAddress)

##
# sudo apt-get update
# sudo apt-get install strongswan strongswan-swanctl charon-systemd
# sudo systemctl status strongswan-swanctl
# sysctl -w net.ipv4.ip_forward=1
#
# connections {
#
#   gw-gw {
#      local_addrs  = 10.0.0.4
#      remote_addrs = 20.9.33.197
#
#      local {
#         auth = psk
#         id = moon.strongswan.org
#      }
#    #  remote {
#    #     auth = psk
#    #     id = sun.strongswan.org
#    #  }
#      children {
#         net-net {
#            local_ts  = 10.0.0.0/22
#            remote_ts = 10.150.0.0/20
#
#            updown = /usr/local/libexec/ipsec/_updown iptables
#            esp_proposals = aes256-sha256-modp1024,aes128-sha256-modp1024
#         }
#      }
#      version = 2
#      mobike = no
#      reauth_time = 10800
#      proposals = aes256-sha256-modp1024,aes128-sha256-modp1024
#      ppk_id = id1
#      reauth_time = 28800
#      rekey_time = 28800
#      over_time = 28800
#   }
#}
#
#secrets {
#   ike-1 {
#      id1 = moon.strongswan.org
#      secret = b2xAbXVuZDBjcnVlbA==
#   }
#   ike-2 {
#      id2 = sun.strongswan.org
#      secret = b2xAbXVuZDBjcnVlbA==
#   }
#}
#
#
fi
