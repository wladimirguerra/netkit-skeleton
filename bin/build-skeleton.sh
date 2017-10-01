#!/bin/bash
#
# build-skeleton.sh
#
# Constrói arquivos e diretórios para emulação com netkit 
#
# Versão 1: Cria subdiretõrios e arquivos a partir do arquivo lab.conf.
#
#
#
# Copyright Wladimir Guerra, 2017

# INICIALIZAÇÃO DE VARIÁVEIS

EMU_PATH=

NODE_COUNT=0

QUAGGA_TEMPLATES_PATH=

# LABCONF_FILE=

VERBOSE=-1

MENSAGEM_USO="
Uso: $(basename $0) [PATH]

Programa constrói estrutura básica para emulação com netkit. 

O diretório de destino [PATH] deve existir e conter o arquivo lab.conf
com os dados da rede que precisa emular. 

É obrigatório fornecer o [PATH].

"

# TRATAMENTO DE OPÇÕES DE LINHA DE COMANDO

while test -n "$1"
do
	case "$1" in

		-V | --version)
			echo -n $(basename "$0")
			# Extrai a versão diretamente dos cabeçalhos do programa
			grep '^# Versão ' "$0" | tail -1 | cut -d : -f 1 | tr -d \#
			exit 0
		;;
		
		-h | --help)
			echo "$MENSAGEM_USO"
			exit 0
		;;

		-v | --verbose)
			VERBOSE=0
		;;

		-n)
			shift
			NODE_COUNT="$1"
		;;

		-t | --template)
			shift
			QUAGGA_TEMPLATES_PATH=$1
		;;

		*)
			# Obtém o path sem a barra final
			EMU_PATH="${1%/}"
			break
		;;
	esac

 # Próximo argumento
 shift
done

# PROCESSAMENTO

# Verifica se caminho existe 
#if [ ! -d "${EMU_PATH:?"[PATH] não fornecido. (Utilize -h para obter ajuda)"}" ] ; then
if [ ! -d "${EMU_PATH}" ] ; then
	echo "Diretório $EMU_PATH inválido. (Utilize -h para obter ajuda)"
	exit 1
fi

echo "Criando estrutura no diretório $EMU_PATH/"
LABCONF_FILE="${EMU_PATH}/lab.conf"

# Verifica se lab.conf existe dentro do diretório fornecido
if [ ! -f "$LABCONF_FILE" ] ; then
	echo "Arquivo $LABCONF_FILE não existe."
	exit 1
fi

# Apaga arquivos existentes no diretório exceto o lab.conf
find "${EMU_PATH}/" -not \( -name 'lab.conf' -or -name "${EMU_PATH}" \) -print0 | xargs -0 -I {} rm -R {} 2> /dev/null

# [ $? -ne 0 ] && echo "Não foi possível apagar todos os arquivos. Tentando montar estrutura mesmo assim."

PREV_NODE_NAME=
# Itera nas linhas do arquivo lab.conf
while read -r line
do
	NODE_NAME=$(echo "$line" | cut -d \[ -f 1)
	NODE_DIR="$EMU_PATH/$NODE_NAME"

	eth_port=$(echo "$line" | grep -oP '\[\K.*?(?=\])')
	startup_file="$EMU_PATH/$NODE_NAME.startup"
	quagga_dir="$NODE_DIR/etc/quagga"
	ospfd_file="$quagga_dir/ospfd.conf"
	
	if [ $VERBOSE -eq 0 ] ; then
		echo "Nó: $NODE_NAME"
		echo "Diretório do Nó: $NODE_DIR"
		echo "Porta ethernet: $eth_port"
	fi
	
	if [ ! "$NODE_NAME" == "$PREV_NODE_NAME" ] ; then
		PREV_NODE_NAME=$NODE_NAME

		# Verifica se diretório do nó existe
		if [ ! -d "$NODE_DIR" ] ; then
			[ $VERBOSE -eq 0 ] && echo "Criando diretório [$NODE_DIR] do nó [$NODE_NAME]"
			mkdir "$NODE_DIR"
			# Verifica se diretório foi criado
			if [ $? -ne 0 ] ; then
				echo "Não foi possível criar diretório $NODE_DIR"
				exit 1
			fi

			# Cria arquivos QUAGGA
			if [ ! -d "$quagga_dir" ] ; then
				[ $VERBOSE -eq 0 ] && echo "Criando diretório $quagga_dir" 
				mkdir -p "$quagga_dir"
				
				# TODO ver se utiliza modelos externos no futuro
				[ $VERBOSE -eq 0 ] && echo "Criando arquivo daemons"
				echo "#
# This file tells the quagga package which daemons to start.
#
# Entries are in the format: <daemon>=(yes|no|priority)
#   0, \"no\"  = disabled
#   1, \"yes\" = highest priority
#   2 .. 10  = lower priorities
# Read /usr/share/doc/quagga/README.Debian for details.
#
# Sample configurations for these daemons can be found in
# /usr/share/doc/quagga/examples/.
#
# ATTENTION: 
#
# When activation a daemon at the first time, a config file, even if it is
# empty, has to be present *and* be owned by the user and group \"quagga\", else
# the daemon will not be started by /etc/init.d/quagga. The permissions should
# be u=rw,g=r,o=.
# When using \"vtysh\" such a config file is also needed. It should be owned by
# group \"quaggavty\" and set to ug=rw,o= though. Check /etc/pam.d/quagga, too.
#
zebra=yes
bgpd=no
ospfd=yes
ospf6d=no
ripd=no
ripngd=no
isisd=no
ldpd=no
" > "$quagga_dir/daemons"

				[ $VERBOSE -eq 0 ] && echo "Criando arquivo bgpd.conf"
				echo "!
hostname $NODE_NAME
password zebra
!
router bgp 1
network 10.0.0.1/30
neighbor 10.0.0.1 remote-as 2
neighbor 10.0.0.1 description Roteador2-AS2
!
log file /var/log/zebra/gbpd.log
!
debug bgp
debug bgp events
debug bgp filters
debug bgp fsm
debug bgp keepalives
debug bgp updates
" > "$quagga_dir/bgpd.conf"
			
			[ $VERBOSE -eq 0 ] && echo "Criando arquivo ripd.conf"
			echo "!
hostname $NODE_NAME
password zebra
!
router rip
!
! habilita a redistribuição de informação
! de vizinhos diretamente conectados
redistribute connected
!
! prefixo das redes que $NODE_NAME pertence
! que serão enviados pelo ripd em multicast
! no AS.
network 10.0.0.0/30
!
log file /var/log/zebra/ripd.log
" > "$quagga_dir/ripd.conf"
			
			[ $VERBOSE -eq 0 ] && echo "Criando arquivo ospfd.conf"
			echo "!
hostname $NODE_NAME
password zebra
!
!O custo (métrica) é de cada interface no roteador
interface eth$eth_port
	ip ospf cost 1 
@interfaces aqui@
router ospf
! Prefixo das redes que R1 pertence que serão
! propagados no AS pelo ospfd
network 10.0.0.0/30
network 10.0.0.4/30
network 10.0.0.8/30
network 10.0.0.12/30
!
log file /var/log/zebra/ripd.log
" > "$ospfd_file"
			fi
		fi

		# Cria arquivo de startup
		[ ! -f "$startup_file" ] && touch "$startup_file" 
	
	else
		# Se a linha é do mesmo nó da linha anterior entra aqui
		
		# Adiciona interface ao arquivo ospfd.conf
		sed -i "s/@interfaces aqui@/interface eth$eth_port\n\tip ospf cost 1\n@interfaces aqui@/" $ospfd_file
	fi

	# Escreve arquivo de startup
	echo "ifconfig eth$eth_port 10.0.0.1/30" >> $startup_file

done < "$LABCONF_FILE"

[ $VERBOSE -eq 0 ] && echo "Linpando arquivos ospfd.conf"

# Acrescenta /etc/init.d/zebra start no fim de todos os arquivos .startup
find $EMU_PATH -name *.startup | \
while IFS= read -r startup_file; do
	echo "/etc/init.d/zebra start" >> $startup_file
done

echo "Estrutura criada com sucesso!"
exit 0
