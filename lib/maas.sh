#!/bin/bash

function maas_id {
    case $1 in
        s02) echo "438xps";;
        s03) echo "p8xe84";;
        s04) echo "xface7";;
	*)
            echo "Unkown host $1";
            exit 1
            ;;
    esac
}

function maas_status {
    maas ubuntu nodes read hostname=$1| grep '"status_name"'| cut -d '"' -f 4
}

function maas_wait_status {
    STATUS=$1
    shift
    HOSTS=$@
    PIDLIST=""

    for i in $HOSTS
    do
        ( while [ "$(maas_status $i)" != "$STATUS" ]; do sleep 1; done ) &
        PIDLIST="$PIDLIST $!"
    done

    wait $PIDLIST
}

function maas_release {
    maas ubuntu machine release $(maas_id $1) > /dev/null
}

function maas_deploy {
    host=$1
    shift
    maas ubuntu machine deploy $(maas_id $host) $@ > /dev/null
}
