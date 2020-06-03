#!/bin/bash

source config.sh
#MASTER="s04"
#MINIONS="s02 s03"
#NODES="$MASTER $MINIONS"

function usage {
	echo "Usage : $0 [plugin]"
	echo "Plugin list available :"
	cd cni/
	ls -1 | grep -E '.*yml$'| sed -e 's/.yml$//' -e 's/^/ - /'
	exit 1
}
function log { echo $(date "+%Y-%m-%d %H:%M:%S") $*; }
function info { log INFO $*; }
function warning { log WARNING $*; }
function error { log ERROR $*; }
function fatal { log FATAL $*; exit 2; }

#==============================================================================
# Pre-flight checks
#==============================================================================

cd $(dirname $0)

source lib/maas.sh
source lib/ssh.sh

NETWORK=$1
[ "$NETWORK" = "" ] && usage
[ -e "cni/$NETWORK.yml" ] || fatal "Unkown network plugin '$NETWORK'"

#==============================================================================
# Deployment
#==============================================================================

info "Starting deployment of k8s with plugin $NETWORK"
info " ( MASTER = $MASTER and MINIONS = $MINIONS )"

info "Waiting for nodes to be ready"
maas_wait_status Ready $NODES

# Distribution to deploy : xenial or bionic
distro=${distro:-bionic}
info "Deploying nodes with Ubuntu $distro"
for i in $NODES
do
	maas_deploy $i distro_series=$distro
done
info "Waiting for nodes to be deployed"
maas_wait_status Deployed $NODES

info "Waiting for SSH access"
lssh_wait $NODES

info "Preparing nodes"
PIDLIST=""
for h in $NODES
do
	(
	info "Node $h start"
	lssh $h "wget -qO - http://10.1.1.1:8080/res/node-prepare.sh | sudo bash" >/tmp/setup.$h.out 2>/tmp/setup.$h.err
	info "Node $h end"
	) &
	PIDLIST="$PIDLIST $!"
done
wait $PIDLIST

info "Downloading 10G.dat on "
lssh $(awk '{print $1}' <<< $MINIONS) wget http://10.1.1.1:8080/10G.dat >/dev/null 2>&1

[ "$NETWORK" = "nok8s" ] && info "Skipping Kubernetes " && exit

info "Deploying master"

KOPT=""
[ -e "cni/$NETWORK.cidr" ] && KOPT="$KOPT --pod-network-cidr $(cat cni/$NETWORK.cidr)"
[ "$KOPT" != "" ] && info "Using master option $KOPT"
lssh $MASTER sudo kubeadm init $KOPT # > /tmp/init.$h.out 2> /tmp/init.$h.err

info "Generating join command"
JOINCMD="$(lssh $MASTER sudo kubeadm token create --print-join-command 2>/dev/null)"

info "Retrieving kubeconfig"
lssh $MASTER sudo cat /etc/kubernetes/admin.conf > kubeconfig 2>/dev/null

sleep 10

info "Joining nodes"
for i in $MINIONS
do
	lssh $i sudo $JOINCMD > /dev/null 2>/dev/null
done

export KUBECONFIG="$(pwd)/kubeconfig"

[ "$NETWORK" = "none" ] && info "Cluster is ready with no CNI" && exit 0

info "Installing CNI $NETWORK"
kubectl apply -f cni/$NETWORK.yml >/dev/null

info "Waiting for nodes to be ready"
while true
do
	kubectl get nodes | grep "NotReady" >/dev/null || break
	sleep 1
done

info "Cluster is now ready with network CNI $NETWORK"
