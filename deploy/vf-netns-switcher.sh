#!/bin/bash

netns=""
pf=""
conf_file=""
pci=""

TIMEOUT="${TIMEOUT:-2}"
POLL_INTERVAL="1"

while test $# -gt 0; do
  case "$1" in

   --netns | -n)
      netns=$2
      shift
      shift
      ;;

   --pf | -d)
      pf=$2
      shift
      shift
      ;;

   --conf-file | -c)
      conf_file=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
vf-netns-switcher.sh --netns <> --pf <> [--conf-file <>]:

	--netns | -n		Netns to switch the interface PFs and VFs to.

	--pf | -d		The PF to switch it and its VFs to the specified netns.

	--conf-file | -c	A file to read confs from, this will override cli flags.

"
      exit 0
      ;;

   *)
      echo "No such option!!"
      echo "Exitting ...."
      exit 1
  esac
done

get_pci_from_net_name(){
    local interface_name=$1
    local worker_netns="${2:-$netns}"

    if [[ -z "$(ip l show $interface_name)" ]];then
        if [[ -n "$(docker exec -t ${worker_netns} ip l show $interface_name)" ]];then
            ip netns exec ${worker_netns} basename $(readlink /sys/class/net/${interface_name}/device)
            return 0
        fi
        echo ""
        return 1
    fi
    basename $(readlink /sys/class/net/${interface_name}/device)
}

netns_create(){
    local worker_netns="${1:-$netns}"

    if [[ ! -e /var/run/netns/$worker_netns ]];then
        local pid="$(docker inspect -f '{{.State.Pid}}' $worker_netns)"

        if [[ -z "$pid" ]];then
            return 1
        fi

        mkdir -p /var/run/netns/
        rm -rf /var/run/netns/$worker_netns
        ln -sf /proc/$pid/ns/net "/var/run/netns/$worker_netns"

        if [[ -z "$(ip netns | grep $worker_netns)" ]];then
            return 1
        fi
    fi
    return 0
}

switch_pf(){
    local pf_name="$1"
    local worker_netns="${2:-$netns}"

    if [[ -z "$(ip netns | grep ${worker_netns})" ]];then
        echo "Namespace $worker_netns not found!"
        return 1
    fi

    if [[ -z "$(ip l show ${pf_name})" ]];then
        if [[ -z "$(docker exec -t ${worker_netns} ip l show ${pf_name})" ]];then
            echo "Interface $pf_name not found..."
            return 1
        fi

        echo "PF ${pf_name} already in namespace $worker_netns!"
    else
        if ! ip l set dev $pf_name netns $worker_netns;then
            echo "Error: unable to set $pf_name namespace to $worker_netns!"
            return 1
        fi
    fi

    if ! docker exec -t ${worker_netns} ip l set $pf_name up;then
        echo "Error: unable to set $pf_name to up!"
        return 1
    fi
    
}

switch_vf(){
    local vf_name="$1"
    local worker_netns="${2:-$netns}"

    if [[ -z "$(ip l show $vf_name)" ]];then
        return 1
    fi

    if ip link set "$vf_name" netns "$worker_netns"; then
      if timeout "$TIMEOUT"s bash -c "until ip netns exec $worker_netns ip link show $vf_name > /dev/null; do sleep $POLL_INTERVAL; done"; then
          return 0
      else
          return 1
      fi
    fi
}

switch_interface_vfs(){
    local pf_name="$1"
    local worker_netns="${2:-$netns}"


    vfs_list=$(ls /sys/bus/pci/devices/$pci/ | grep virtfn)

    if [[ -z "${vfs_list}" ]];then
        echo "Warning: No VFs found for interface $pf_name!!"
        return 0
    fi

    for vf in $vfs_list;do
        local vf_interface="$(ls /sys/bus/pci/devices/$pci/$vf/net)"

        if [[ -n "$vf_interface" ]];then
            echo "Switching $vf_interface to namespace $worker_netns..."
            sleep 2
            if ! switch_vf "$vf_interface" "$worker_netns";then
                echo "Error: could not switch $vf_interface to namespace $worker_netns!"
            else
                echo "Successfully switched $vf_interface to namespace $worker_netns"
            fi
        fi
    done
}

read_confs(){
    local conf_file="$1"

    for key in $(yq r "$conf_file" | cut -d ":" -f 1);do
        eval $key="$(yq r $conf_file $key)"
    done
}

variables_check(){
    local status=0

    check_empty_var "netns"
    let status=$status+$?
    check_empty_var "pf"
    let status=$status+$?

    return $status
}

check_empty_var(){
    local var_name="$1"

    if [[ -z "${!var_name}" ]];then
        echo "$var_name is empty..."
        return 1
    fi

    return 0
}

main(){
    local status=0

    while true;do
        switch_interface_vfs "$pf" "$netns"
        sleep $TIMEOUT
    done
    return $status
}

read_confs "$conf_file"

variables_check
let status=$status+$?

if [[ "$status" != "0" ]];then
    echo "ERROR: empty var..."
    exit $status
fi

pci=$(get_pci_from_net_name "$pf" "$worker_netns")

if [[ -z "${pci}" ]];then
    echo "Error: could not get pci address of interface $pf!!"
    exit 1
fi

netns_create
let status=$status+$?
if [[ "$status" != "0" ]];then
    echo "ERROR: failed to create netns..."
    exit $status
fi

switch_pf "$pf" "$netns"
let status=$status+$?
if [[ "$status" != "0" ]];then
    echo "ERROR: failed to switch pf $pf to the $netns namespace..."
    exit $status
fi

main
