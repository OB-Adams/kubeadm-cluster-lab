#!/usr/bin/env bash
# Checks every milestone 1 acceptance criterion on one node. Runs as root on
# the node. playbooks/verify-node-prep.yml sets the inputs below; to run it by
# hand, export them first.
set -u

: "${NODE_NAME:?}" "${NODE_ROLE:?}" "${EXPECTED_VERSION:?}" "${POD_CIDR:?}"
: "${EXPECTED_PORTS:?}" "${NODES:?}" "${EXPECTED_OS_ID:?}" "${EXPECTED_OS_MAJOR:?}"
FW_ZONE="${FW_ZONE:-public}"

passed=0
failed=0

check() {
  local desc=$1 output
  shift
  if output=$("$@" 2>&1); then
    printf 'PASS  %s\n' "$desc"
    passed=$((passed + 1))
  else
    printf 'FAIL  %s\n' "$desc"
    if [ -n "$output" ]; then
      printf '%s\n' "$output" | tail -n 5 | sed 's/^/      | /'
    fi
    failed=$((failed + 1))
  fi
}

in_list() {
  local needle=$1
  shift
  printf '%s\n' "$@" | grep -qxF -- "$needle"
}

printf '== %s (%s) %s\n' "$NODE_NAME" "$NODE_ROLE" "$(date '+%Y-%m-%d %H:%M:%S')"

# Base system
# shellcheck source=/dev/null
os_id=$(. /etc/os-release && echo "$ID")
# shellcheck source=/dev/null
os_major=$(. /etc/os-release && echo "${VERSION_ID%%.*}")
check "OS is $EXPECTED_OS_ID $EXPECTED_OS_MAJOR" test "$os_id $os_major" = "$EXPECTED_OS_ID $EXPECTED_OS_MAJOR"
check "hostname is $NODE_NAME" test "$(hostname)" = "$NODE_NAME"
for node in $NODES; do
  check "resolves $node" getent hosts "$node"
done
check "SELinux is Enforcing" test "$(getenforce)" = Enforcing

# Time
check "chronyd is running" systemctl is-active --quiet chronyd
check "clock is NTP synchronised" test "$(timedatectl show -p NTPSynchronized --value)" = yes

# Swap
check "no active swap" test -z "$(swapon --noheadings)"
check "no active swap entry in /etc/fstab" bash -c "! grep -Pq '^[^#\s]\S*\s+\S+\s+swap\s' /etc/fstab"

# Kernel
for module in overlay br_netfilter; do
  check "module $module loaded" grep -q "^$module " /proc/modules
  check "module $module loads at boot" grep -qx "$module" /etc/modules-load.d/k8s.conf
done
for key in net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables; do
  check "$key = 1" test "$(sysctl -n "$key")" = 1
done

# firewalld
check "firewalld is running" systemctl is-active --quiet firewalld
iface=$(ip route show default | awk '{print $5; exit}')
check "default interface $iface is in zone $FW_ZONE" test "$(firewall-cmd --get-zone-of-interface="$iface")" = "$FW_ZONE"
open_ports=$(firewall-cmd --zone="$FW_ZONE" --list-ports)
for port in $EXPECTED_PORTS; do
  # shellcheck disable=SC2086
  check "port $port open in $FW_ZONE" in_list "$port" $open_ports
done
trusted_sources=$(firewall-cmd --zone=trusted --list-sources)
# shellcheck disable=SC2086
check "pod CIDR $POD_CIDR is a trusted source" in_list "$POD_CIDR" $trusted_sources

# containerd
check "containerd is running" systemctl is-active --quiet containerd
check "containerd is enabled" systemctl is-enabled --quiet containerd
check "containerd uses the systemd cgroup driver" bash -c "containerd config dump | grep -q 'SystemdCgroup = true'"
check "containerd labels containers for SELinux" bash -c "containerd config dump | grep -q 'enable_selinux = true'"
check "crictl is installed" command -v crictl
check "CRI plugin answers crictl" crictl info

# Kubernetes packages
for pkg in kubelet kubeadm kubectl; do
  check "$pkg is $EXPECTED_VERSION" test "$(rpm -q --qf '%{VERSION}' "$pkg")" = "$EXPECTED_VERSION"
done
check "Kubernetes packages excluded from dnf upgrades" grep -Eq '^exclude *=.*\bkubeadm\b' /etc/yum.repos.d/kubernetes.repo
check "kubelet is enabled" systemctl is-enabled --quiet kubelet

printf '== %s: %d passed, %d failed\n' "$NODE_NAME" "$passed" "$failed"
[ "$failed" -eq 0 ]
