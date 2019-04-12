sudo apt install -y socat iproute2 ipvsadm

sudo ip netns add con1
sudo ip netns add con2

sudo ip link add veth10 type veth peer name veth11
sudo ip link add veth20 type veth peer name veth21

sudo ip link set veth11 netns con1
sudo ip link set veth21 netns con2

sudo ip netns exec con1 ip addr add 80.0.1.2/24 dev veth11
sudo ip netns exec con2 ip addr add 80.0.1.3/24 dev veth21

sudo ip netns exec con1 ip link set lo up
sudo ip netns exec con2 ip link set lo up

sudo ip link add name br0 type bridge

sudo ip link set dev veth10 master br0
sudo ip link set dev veth20 master br0

sudo ip addr add 80.0.1.1/24 dev br0

sudo ip link set br0 up

sudo ip link set veth10 up
sudo ip link set veth20 up

sudo ip netns exec con1 ip link set dev veth11 up
sudo ip netns exec con2 ip link set dev veth21 up

sudo ip netns exec con1 ip route add default via 80.0.1.1 dev veth11
sudo ip netns exec con2 ip route add default via 80.0.1.1 dev veth21

sudo socat TUN:192.168.200.2/24,iff-up TCP:${THE_OTHER_NODE_IP}:9001,bind=${CURRENT_IP}:9001 &

sudo ip route add 80.0.0.0/24 via 192.168.200.2 dev tun0

mkdir C D
echo 'C' >> C/index.html
echo 'D' >> D/index.html

docker run --rm -d -v "/home/kubo/C:/usr/share/nginx/html" --name nginx-C nginx
docker run --rm -d -v "/home/kubo/D:/usr/share/nginx/html" --name nginx-D nginx
