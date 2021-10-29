# instruções de uso

## Notas
1. Existem 3 arquivos para configurar parte do setup. 
2. Os scripts foram desenvolvidos apenas para este cenario de estudos e não possuem controles de automação.
3. A seguinte sequencia precisa ser utilizada
    * **env-config.sh**: Responsavel pelo setup da VNET com 2 subets (AKS e LinuxVMs) e uma NSG para filtrar o IP de origem para conexão SSH da primeira VM do setup IaaS (não aplicavel para o AKS).
    * **aks-config.sh**: Responsavel pelo setup de um cluster AKS
    * **linux-vm.sh**: Resposavel pelo setup de VMs linus Ubuntu para instalação manual de um cluster Kubernetes

## Pre-requisitos
1. Desktop ou Maquina virtual com um shell linux. Meu setup utiliza um desktop Windows 10 ou 11 com o Windows Subsystem for Linux instalado.
2. o command line [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/). A versão utilizada foi **2.28.0**
3. Uma subscription no Azure. [Subscription Free](https://azure.microsoft.com/pt-br/free/)


## env-config.sh

No shell linux executar:`bash env-config.sh <rgname> <região Azure>`.


**rgname**: String com o nome do resource group que será criado para os objetos da virtual network.


**região Azure**: String com o short name da região onde o componente deve ser criado. Utilizar o comando `az account list-locations` para listar as opções.

## aks-config.sh ##


## linux-vm.sh ##

  
  

  

