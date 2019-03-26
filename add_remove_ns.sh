#!/bin/bash -e             
conf_file=/etc/cni/net.d/mlnx.conf
netsp='mellanox'
NETMASK='10.56.227'
VER='0.2.0'
PATH=$PATH:/usr/sbin:/usr/local/go/bin
GOROOT=${GOROOT:-/usr/local/go}
GOPATH=${GOPATH:-/usr/local/go/go}
CNITOOLPATH=${/opt/cni:-/home_stack/cni/cni/cnitool/}

# ConnectX-5
HCA=MT27800

status=0
pci=$(lspci |grep Mell|egrep $HCA |grep -v Virtual |awk '{print $1}'|head -n1)
pf=$(ls -l /sys/class/net/| grep $pci|awk '{print $9}')

sudo sh -c "echo 0 > /sys/class/net/$pf/device/sriov_numvfs"
sudo sh -c "echo 4 > /sys/class/net/$pf/device/sriov_numvfs"

IBDEV0=$(ibdev2netdev)
vf_count0=$(ibdev2netdev |wc -l)
sudo rm -f $conf_file

cat > $conf_file  <<EOF
{
  "type": "sriov",
  "name": "sriov-network",
  "master":"$pf",
  "ipam": {
    "type": "host-local",
    "subnet": "$NETMASK.0/24",
    "routes": [{
      "dst": "0.0.0.0/0"
    }],
    "gateway": "$NETMASK.1"
  }
}
EOF

echo "SRIOV CNI config file $conf_file:"
cat $conf_file

echo "Deleting namespace"
echo "# sudo ip netns del $netsp"
sudo ip netns del $netsp 2>&1|tee  > /dev/null

echo "Adding new namespace"
echo "# sudo ip netns add $netsp"
sudo ip netns add $netsp
echo "Show namespaces"
echo "# ip netns show"
ip netns show

echo "Add sriov-network to namespace"
echo "# sudo CNI_PATH=/opt/cni/bin/ $CNITOOLPATH/cnitool add sriov-network /var/run/netns/$netsp"
sudo CNI_PATH=/opt/cni/bin/ $CNITOOLPATH/cnitool add sriov-network /var/run/netns/$netsp

echo "Show new namespaces"
echo "# sudo ip netns exec $netsp ifconfig -a"
sudo ip netns exec $netsp ifconfig -a
IP=$(sudo ip netns exec $netsp ip addr show|grep 'inet '|awk '{print $2}'|cut -d'/' -f1)
echo "IP is $IP"
if [ ! -z "${IP##*$NETMASK*}" ]; then
  echo "ERROR, IP $IP is not found"
  status=1
fi

IBDEV1=$(ibdev2netdev)
vf_count1=$(ibdev2netdev |wc -l)

cat > $conf_file  <<EOF
{
"cniVersion":"$VER",
  "type": "sriov",
  "name": "sriov-network",
  "master":"$pf",
  "ipam": {
    "type": "host-local",
    "subnet": "$NETMASK.0/24",
    "routes": [{
      "dst": "0.0.0.0/0"
    }],
    "gateway": "$NETMASK.1"
  }
}
EOF

echo "Delete sriov-network from namespace"
echo "# sudo CNI_PATH=/opt/cni/bin/ $CNITOOLPATH/cnitool delete sriov-network /var/run/netns/$netsp"
sudo CNI_PATH=/opt/cni/bin/ $CNITOOLPATH/cnitool delete sriov-network /var/run/netns/$netsp

echo "Delete namespace"
echo "# sudo ip netns del $netsp"
sudo ip netns del $netsp
IBDEV2=$(ibdev2netdev)
vf_count2=$(ibdev2netdev |wc -l)

echo "VF count at start was $vf_count0"
echo "VF count after adding was $vf_count1"
echo "VF count at end was $vf_count2"
let vf_count4=vf_count1+1

if [[ $vf_count0 -eq $vf_count2 && $vf_count0 -eq $vf_count4 ]]; then
   echo "VF counts are OK"
else
   status=1
   echo "VF was not returned or taken correctly"
fi
exit $status
