# instruções de uso

## UPDATE
05/06/2023: VM Size e OS atualizados para refletir os requisitos atuais das provas.

## Notas
1. Existem 3 arquivos para configurar parte do setup. 
2. Os scripts foram desenvolvidos apenas para este cenario de estudos e não possuem controles de automação.
3. A seguinte sequencia precisa ser utilizada
    * **env-config.sh**: Responsavel pelo setup da VNET com 2 subets (AKS e LinuxVMs) e uma NSG para filtrar o IP de origem para conexão SSH da primeira VM do setup IaaS (não aplicavel para o AKS).
    * **aks-config.sh**: Responsavel pelo setup de um cluster AKS
    * **linux-vm.sh**: Resposavel pelo setup de VMs linux Ubuntu para instalação manual de um cluster Kubernetes

## Pre-requisitos
1. Desktop ou Maquina virtual com um shell linux. Meu setup utiliza um desktop Windows 10 ou 11 com o Windows Subsystem for Linux instalado.
2. Instalar o Azure CLI no ambiente LINUX (caso utilize o WSL por exemplo) [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/). versão utilizada: **2.28.0**
3. Uma subscription no Azure. Caso não possua uma, utilize uma [Subscription Gratuita*](https://azure.microsoft.com/pt-br/free/)

===============	
## env-config.sh

No shell linux executar:   `bash env-config.sh <rgname> <região Azure>`.

Este script vai identificar o IP de internet da conexão e liberar na network security group (nsg) da VNET o acesso ao SSH da primeira VM. POr isto, sempre que o seu IP alterar, precisa ajustar a regra da NSG (em breve terá um script para isto).

### Parametros ###
* **rgname**: String com o nome do resource group que será criado para os objetos da virtual network.
* **região Azure**: String com o short name da região onde o componente deve ser criado. Utilizar o comando `az account list-locations` para listar as opções.

### Exemplo ###
`bash env-config.sh k8slab-share eastus2`

===============	
## aks-config.sh ##
No shell linux executar:   `bash aks-config.sh <rgname AKS> <Nome AKS> <região Azure> <rgname da vnet> <versão Kubertes> <quantidade workers>`.

Uma instancia do Azure [Kubernetes Services - AKS](https://docs.microsoft.com/en-us/azure/aks/) será instalada com 2 node/workers e o download do KubeConfig será feito para o caminho padrão. Se já existir um arquivo, sera feito o merge dos arquivos.

## Pre requisito ##
1. instalar o kubectl:  `az aks install-cli`
2. Verificar qual versão do Kubernetes deseja instalar:  `az aks get-versions --location eastus2`

### Parametros ###
* **rgname AKS**: String com o nome do resource group que será criado para o AKS (o setup cria um segundo RG para os objetos de compute do AKS).
* **Nome AKS**: String com o nome utilizado para definir o AKS.
* **região Azure**: String com o short name da região onde o componente deve ser criado. utilizar a mesma região da VNET.
* **rgname da vnet**: String com o nome do resource group que contem a virtual network.
* **versão Kubertes** 
* **quantidade VMs**: Numero de workers que devem ser criados. Utilizar entre 2 e 4.  

### Exemplo ###
`bash aks-config.sh aksrg aksdemo eastus2 k8slab-share 1.22.1 2`

===============	
## linux-vm.sh ##
No shell linux executar:   `bash linux-vm.sh <rgname para VMs> <Nome base VMs> <região Azure> <rgname da vnet> <quantidade VMs>`.

Ao concluir a instalação das VMs, o script vai fazer o SSH para a primeira maquina virtual utilizando as chaves SSH do diretorio .ssh (criada ou existentes). 
Para logar novamente no SSH, basta executar o comando `ssh <ip do load balancer>`

### Parametros ###
* **rgname para Vms**: String com o nome do resource group que será criado para os objetos Virtual Machine, LoadBalancer, PublicIP.
* **Nome base Vms**: String com o prefixo utilizado para definir o nome das maquinas virtuais.
* **região Azure**: String com o short name da região onde o componente deve ser criado. utilizar a mesma região da VNET.
* **rgname da vnet**: String com o nome do resource group que contem a virtual network.
* **quantidade VMs**: Numero de VMs que devem ser criadas. Utilizar entre 2 e 4.  

### Exemplo ###
`bash linux-vm.sh vmrg k8svm eastus2 k8slab-share 2`


### Commandos uteis do setup do Kubernetes nas VMs (Demo video Cloud Talk)

1. ### Resolução estatica para cluster01.k8slab.local ###
   sudo /bin/bash -c "echo 10.150.0.132 cluster01.k8slab.local > /etc/hosts"

2. ### instalar kubeadm, kubelet e kubectl e com opcao de escolher uma versao diferente
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
    
    sudo apt-cache show kubeadm | grep -i version | less
    
    sudo apt-get update && sudo apt-get install -y kubeadm=1.21.x-00 kubelet=1.21.x-00 kubectl=1.21.x-00 && sudo apt-mark hold kubeadm kubelet kubectl

3. ### instalar o containerd ###
    
    1. opção 1 com gerenciador de pacotes:
    https://kubernetes.io/docs/setup/production-environment/container-runtimes/
    
    sudo apt-get update && sudo apt install containerd

    2. opção 2 manual
    https://github.com/containerd/containerd/blob/main/docs/getting-started.md

    wget https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz
    sudo tar Czxvf /usr/local containerd-1.7.2-linux-amd64.tar.gz
    wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    sudo mv containerd.service /usr/lib/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd
    sudo systemctl status containerd

    wget https://github.com/opencontainers/runc/releases/download/v1.1.7/runc.amd64
    sudo install -m 755 runc.amd64 /usr/local/sbin/runc

    sudo mkdir -p /etc/containerd/
    containerd config default | sudo tee /etc/containerd/config.toml

    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

    sudo systemctl restart containerd

4. ### Exemplo de Kubeadm init para network flannel
    sudo kubeadm init --control-plane-endpoint cluster01.k8slab.local:6443 --upload-certs --pod-network-cidr=10.244.0.0/16

5. ### Setup Flannel ###
    kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml

