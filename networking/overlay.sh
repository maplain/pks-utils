sudo ip netns add con1
sudo ip netns add con2

sudo ip link add veth10 type veth peer name veth11
sudo ip link add veth20 type veth peer name veth21

sudo ip link set veth11 netns con1
sudo ip link set veth21 netns con2

sudo ip netns exec con1 ip addr add 10.0.0.2/24 dev veth11
sudo ip netns exec con2 ip addr add 10.0.0.3/24 dev veth21

sudo ip netns exec con1 ip link set lo up
sudo ip netns exec con2 ip link set lo up

sudo ip link add name br0 type bridge

sudo ip link set dev veth10 master br0
sudo ip link set dev veth20 master br0

sudo ip addr add 10.0.0.1/24 dev br0

sudo ip link set br0 up

sudo ip link set veth10 up
sudo ip link set veth20 up

sudo ip netns exec con1 ip link set dev veth11 up
sudo ip netns exec con2 ip link set dev veth21 up

sudo ip netns exec con1 ip route add default via 10.0.0.1 dev veth11
sudo ip netns exec con2 ip route add default via 10.0.0.1 dev veth21

#sudo socat TUN:192.168.200.1/24,iff-up UDP:10.161.81.5:9000,bind=10.161.151.92:9000

#also need to setup routes
# sudo ip route add 10.0.1.0/24 via 192.168.200.1 dev tun0
