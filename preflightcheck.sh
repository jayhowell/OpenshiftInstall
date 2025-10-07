#!/usr/bin/env bash

# Assisted Installer Preflight Check Script
# Run this from your bastion host before starting the Assisted Installer.
# It checks DNS resolution and TCP port connectivity to cluster endpoints and nodes.

# ------------------------------
# CONFIGURATION
# ------------------------------

# Replace these with your environment details
CLUSTER_DOMAIN="example.openshift.example.com"   # base domain for your cluster
API_VIP="api.${CLUSTER_DOMAIN}"
API_INT_VIP="api-int.${CLUSTER_DOMAIN}"
APPS_WILDCARD="console-openshift-console.apps.${CLUSTER_DOMAIN}"

# Add your node hostnames or IPs (masters/workers)
NODES=(
  "master-0.${CLUSTER_DOMAIN}"
  "master-1.${CLUSTER_DOMAIN}"
  "master-2.${CLUSTER_DOMAIN}"
  "worker-0.${CLUSTER_DOMAIN}"
  "worker-1.${CLUSTER_DOMAIN}"
  "worker-2.${CLUSTER_DOMAIN}"
)

# Common ports used by the installer and cluster
PORTS=(
  22      # SSH
  443     # HTTPS / API
  80      # HTTP (apps)
  6443    # Kubernetes API
  22623   # Machine Config Server
  3128    # Optional proxy
)

# ------------------------------
# FUNCTIONS
# ------------------------------

check_dns() {
  local host=$1
  echo -n "[DNS] Checking ${host}... "
  if dig +short "${host}" >/dev/null; then
    ip=$(dig +short "${host}" | tail -n1)
    echo "OK (${ip})"
  else
    echo "FAILED"
  fi
}

check_port() {
  local host=$1
  local port=$2
  timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null
  if [ $? -eq 0 ]; then
    echo "  [PORT ${port}] OPEN"
  else
    echo "  [PORT ${port}] CLOSED or FILTERED"
  fi
}

# ------------------------------
# MAIN EXECUTION
# ------------------------------

echo "======================================"
echo " OpenShift Assisted Installer Preflight"
echo "======================================"
echo ""

echo "Checking DNS entries..."
check_dns "${API_VIP}"
check_dns "${API_INT_VIP}"
check_dns "${APPS_WILDCARD}"

for node in "${NODES[@]}"; do
  check_dns "${node}"
done

echo ""
echo "Checking port connectivity..."
for node in "${NODES[@]}"; do
  echo "Checking ${node}:"
  for port in "${PORTS[@]}"; do
    check_port "${node}" "${port}"
  done
done

echo ""
echo "Verifying VIP ports..."
for host in "${API_VIP}" "${API_INT_VIP}"; do
  echo "Checking ${host}:"
  for port in 6443 22623; do
    check_port "${host}" "${port}"
  done
done

echo ""
echo "Preflight check complete."
