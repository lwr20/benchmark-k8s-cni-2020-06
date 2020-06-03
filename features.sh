#!/bin/bash

kubectl get ns netpol 2>/dev/null && echo "Existing netpol namespace, aborting ..." && exit

K="kubectl run -n netpol --restart=Never"

echo "Initializing"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  creationTimestamp: null
  name: netpol
spec: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-ingress
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      run: server-with-netpol
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          run: authorized-client # Authorized Client
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-egress
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      run: client-with-netpol
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          run: authorized-server
EOF

echo "Retrieving MTU"
MTU=$($K -it --rm debug --image=infrabuilder/netbench:client -- ip a 2>/dev/null | grep "eth0.*mtu" | sed -e 's/.*mtu //' -e 's/[^0-9]*$//')

# Starting server
function start_srv {
	NAME=$1
	$K $NAME --image=infrabuilder/netbench:server-http >/dev/null 2>/dev/null
	while true; do kubectl -n netpol get pod/$NAME |grep Running >/dev/null && break; sleep 1; done
	sleep 1
	kubectl get -n netpol pod/$NAME -o jsonpath='{.status.podIP}'
}
function client {
	NAME=$1
	SRVIP=$2
	$K -it --rm --image=infrabuilder/netbench:client \
	$1 -- curl --connect-timeout 5 $2 2>/dev/null | grep "Welcome to nginx" > /dev/null && echo yes || echo no
}
function del {
	NAME=$1
	kubectl -n netpol delete po/$NAME 2>/dev/null >/dev/null
}

echo "Starting ingress/egress tests"
#=====================================================
# Egress
#=====================================================
# Scenario :
#
# A server pod with ingress netpol should be accessed
# by an authorized client, but should not be accessed
# by a 'not authorized' client
#
# +-------------------+              +------------------+
# | Authorized client +---------+--->+Server with netpol|
# +-------------------+         |    +------------------+
#                               |
# +-------------------+         |
# |Unauthorized client+-----X---+
# +-------------------+
#=====================================================

# Ingress
IP=$(start_srv server-with-netpol)
INGRESS=no
if [ "$(client authorized-client $IP)" = "yes" ]
then
	echo "ING SUCCESS: 'Authorized' client 'can' access protected server"
	if [ "$(client unauthorized-client $IP)" = "no" ]
	then
		echo "ING SUCCESS: 'Unauthorized' client 'cannot' access protected server"
		INGRESS=yes
	else
		echo "ING FAIL: 'Unauthorized' client 'can' access protected server"
	fi
else
	echo "ING FAIL: 'Authorized' client cannot access protected server"
fi
del server-with-netpol
echo "INGRESS = $INGRESS"


#=====================================================
# Egress
#=====================================================
# Scenario :
#
# A client pod with egress netpol should access to
# an authorized server, but should not access to a
# 'not authorized' server
#
# +------------------+          +-------------------+
# |Client with netpol+--+------>+ Authorized server |
# +------------------+  |       +-------------------+
#                       |
#                       |       +-------------------+
#                       +--X--> |Unauthorized server|
#                               +-------------------+
#=====================================================
IPA=$(start_srv authorized-server)
IPU=$(start_srv unauthorized-server)
EGRESS=no

if [ "$(client client-with-netpol $IPA)" = "yes" ]
then
	echo "EG SUCCESS: Protected client 'can' access 'authorized' server"
	if [ "$(client client-with-netpol $IPU)" = "no" ]
	then
		echo "EG SUCCESS: Protected client 'cannot' access 'unauthorized' server"
		EGRESS=yes
	else

		echo "EG FAIL: Protected client 'can' access 'unauthorized' server"
	fi
else
	echo "EG FAIL: Protected client 'cannot' access 'authorized' server"
fi
del authorized-server
del unauthorized-server

echo "Cleaning"
kubectl delete ns netpol

echo "Result :"
echo -e "MTU : $MTU\nIngress : $INGRESS\t Egress : $EGRESS"
