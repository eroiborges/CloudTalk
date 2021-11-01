case $1 in
   "lbip") az network public-ip list | grep kube-ip | awk '{print $4}';;
   "myip") curl -s -k ifconfig.me;;
   "updatensg") 
      IP1="$(az network nsg list -o tsv --query "[?name=='kube-nsg'].{IP:securityRules[0].sourceAddressPrefix}")"
      IP2="$(curl -s -k ifconfig.me)"

      if [[ $IP1 = $IP2 ]];
      then
        echo "seu IP:$IP1 é o IP liberado na NSG"
      else
        echo "Ajustando IP....."
        rgname="$(az network nsg list -o tsv --query "[?name=='kube-nsg'].{RG:resourceGroup}")"
        az network nsg rule update -g $rgname --nsg-name kube-nsg -n kube-nsg-Rule --source-address-prefix "$IP2"
      fi;;
   "sshnode") ssh $(az network public-ip list | grep kube-ip | awk '{print $4}') -o "StrictHostKeyChecking no";;
   *) echo "Sorry, Select a option lbip or myip or updatensg or sshnode";;
esac


