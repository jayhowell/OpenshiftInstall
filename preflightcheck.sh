#!/usr/bin/env bash

# Assisted Installer Preflight Check Script (emoji + robust DNS)
# Run from your bastion host before starting the Assisted Installer.

# ------------------------------
# CONFIGURATION
# ------------------------------
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
# OUTPUT STYLING
# ------------------------------
# Use color when possible; emojis always.
if [ -t 1 ]; then
  GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; RESET="\033[0m"
else
  GREEN=""; RED=""; YELLOW=""; RESET=""
fi
OK_ICON="✅"
FAIL_ICON="❌"

# ------------------------------
# FUNCTIONS
# ------------------------------

# Resolve a hostname to an IP (prefers system NSS via getent; falls back to dig)
resolve_host() {
  local host="$1"
  local ip=""

  if command -v getent >/dev/null 2>&1; then
    # getent returns non-zero if not found; first column is the IP
    ip="$(getent hosts "$host" | awk '{print $1; exit}')"
  fi

  if [[ -z "$ip" ]] && command -v dig >/dev/null 2>&1; then
    # Prefer A then AAAA; ensure we only accept IP-looking answers
    ip="$(dig +short A "$host" | awk '/^[0-9.]+$/{print; exit}')"
    if [[ -z "$ip" ]]; then
      ip="$(dig +short AAAA "$host" | awk '/:/ {print; exit}')"
    fi
  fi

  printf "%s" "$ip"
}

check_dns() {
  local host="$1"
  printf "[DNS] Checking %s... " "$host"

  local ip
  ip="$(resolve_host "$host")"

  if [[ -n "$ip" ]]; then
    printf "${GREEN}%s OK${RESET} (%s)\n" "$OK_ICON" "$ip"
  else
    printf "${RED}%s FAILED${RESET} to resolve %s\n" "$FAIL_ICON" "$host"
  fi
}

check_port() {
  local host="$1"
  local port="$2"

  # Prefer nc if available for clearer semantics; fall back to /dev/tcp
  if command -v nc >/dev/null 2>&1; then
    nc -z -w3 "$host" "$port" >/dev/null 2>&1
    rc=$?
  else
    timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
    rc=$?
    # Map timeout(124) to failure
    [[ $rc -eq 124 ]] && rc=1
  fi

  if [[ $rc -eq 0 ]]; then
    printf "  ${GREEN}%s [PORT %s] OPEN${RESET}\n" "$OK_ICON" "$port"
  else
    printf "  ${RED}%s [PORT %s] CLOSED or FILTERED${RESET}\n" "$FAIL_ICON" "$port"
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

