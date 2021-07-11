#!/bin/bash
# This scripts create vfs on the interface and switch them to switchdev mode
# it accepts two parameters, the first is the name of the interface and the
# second is the number of vfs

interface=""
vfs_num=""
set_vfs_macs_flag="false"
isSwitchdev="false"

vendor_id=""
vfs_pci_list=""
interface_pci=""

##################################################
##################################################
##################   input   #####################
##################################################
##################################################


while test $# -gt 0; do
  case "$1" in

   --interface | -i)
      interface=$2
      shift
      shift
      ;;

   --vfs | -v)
      vfs_num=$2
      shift
      shift
      ;;

   --set-vfs-macs)
      set_vfs_macs_flag="true"
      shift
      ;;

   --switchdev)
      isSwitchdev="true"
      shift
      ;; 
   

   --help | -h)
      echo "
create_vfs -i <interface> -v <number of vfs> [--set-vfs-macs]: create vfs on the \
specified interface and switch them to switchdev mode.

options:

	--interface | -i) <interface>			The interface to \
enable the switchdev mode on.

        --vfs-num | -v) <vfs number>			The number of vfs \
to create on the interface.

        --set-vfs-macs)					Set vfs macs for \
rdma exclusive mode bug.

        --switchdev)					Enable switchdev \
mode for the PF.
"
      exit 0
      ;;

   *)
      echo "No such option!!"
      echo "Exitting ...."
      exit 1
  esac
done

##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


check_interface(){
   if [[ ! -d /sys/class/net/"$interface" ]]
   then
      echo "ERROR: No interface named $interface exist on the machine, \
please check the interface name spelling, or make sure the \
interface really exist."
      echo "Exiting ...."
      exit 1
   fi
}

check_vendor(){
   vendor_id=$(cat /sys/class/net/"$interface"/device/vendor)
   if [[ "$vendor_id" != "0x15b3" ]]
   then
      echo "ERROR: the card is not a Mellanox product!!"
      echo "Exiting ...."
      exit 1
   fi
}

configure_vfs(){
   if [ $(cat /sys/class/net/"$interface"/device/sriov_numvfs) != "0" ]
   then
      echo 0 > /sys/class/net/"$interface"/device/sriov_numvfs
      sleep 2
   fi
   echo "$vfs_num" > /sys/class/net/"$interface"/device/sriov_numvfs
}

set_vfs_macs(){
   let last_index=$vfs_num-1
   for i in $(seq 0 $last_index); do
      ip link set $interface vf $i mac 00:22:00:11:22:$(printf '%02x' $i)
      pci=$(readlink /sys/class/net/$interface/device/virtfn$i | sed 's/..\///')
      echo "$pci" > /sys/bus/pci/drivers/mlx5_core/unbind
      echo "$pci" > /sys/bus/pci/drivers/mlx5_core/bind
   done
}

get_vfs_pcis(){
   grep PCI_SLOT_NAME /sys/class/net/"$interface"/device/virtfn*/uevent | cut -d'=' -f2
}

unbind_vfs(){
   local status=0

   for pci in $(get_vfs_pcis)
   do
      echo "$pci" > /sys/bus/pci/drivers/mlx5_core/unbind
      let status=$status+$?
   done

   return $status
}

enable_switchdev_for_interface(){
   interface_pci=$(grep PCI_SLOT_NAME /sys/class/net/"$interface"/device/uevent\
                  | cut -d'=' -f2 -s)
   /usr/sbin/devlink dev eswitch set pci/"$interface_pci" mode switchdev
   return $?
}

bind_vfs(){
   local status=0

   for pci in $(get_vfs_pcis)
   do
      echo "$pci" > /sys/bus/pci/drivers/mlx5_core/bind
      let status=$status+$?
   done

   return $status
}

enable_switchdev(){
    if ! unbind_vfs;then return 1;fi

    if ! enable_switchdev_for_interface;then return 1;fi

    if ! bind_vfs;then return 1;fi
}
##################################################
##################################################
##############   validation   ####################
##################################################
##################################################


if [[ -z "$interface" ]]
then
   echo "No interface was provided, please provide one using the \
--interface or the -i options."
   echo "Exiting ...."
   exit 1
fi

if [[ -z "$vfs_num" ]]
then
   echo "The number of vfs was not specified, please specify it using the \
--vfs or -v options."
   echo "Exiting ...."
   exit 1
fi

check_interface

check_vendor


##################################################
##################################################
####################   MAIN   ####################
##################################################
##################################################


set -e
set -x

configure_vfs

if [[ "$set_vfs_macs_flag" == "true" ]];then
   set_vfs_macs
fi

if [[ "$isSwitchdev" == "true" ]];then
   enable_switchdev
fi

ip link set "$interface" up

