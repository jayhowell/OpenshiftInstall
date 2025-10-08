#!/usr/bin/env bash
#
# check_redhat_cert_chain.sh
# Verify SSL certificate chains for critical Red Hat and Quay endpoints on port 443
# Requires: openssl, timeout, grep, awk, sed
#
# Usage: ./check_redhat_cert_chain.sh
#

# List of hosts to check
HOSTS=(
  "registry.redhat.io"
  "access.redhat.com"
  "registry.access.redhat.com"
  "quay.io"
  "cdn.quay.io"
  "cdn01.quay.io"
  "cdn02.quay.io"
  "cdn03.quay.io"
  "cdn04.quay.io"
  "cdn05.quay.io"
  "cdn06.quay.io"
  "sso.redhat.com"
  "cert-api.access.redhat.com"
  "api.access.redhat.com"
  "infogw.api.openshift.com"
  "console.redhat.com"
)

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

echo "🔍 Checking certificate chain for Red Hat and Quay endpoints..."
echo "-------------------------------------------------------------"
echo ""

for host in "${HOSTS[@]}"; do
  echo "🟢 Checking ${host}:443 ..."

  # Use timeout to prevent hang
  output=$(timeout 10 openssl s_client -connect "${host}:443" -servername "${host}" -showcerts </dev/null 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo -e "  ${RED}❌ Connection failed or timed out${NC}"
    echo ""
    continue
  fi

  # Check if certificate chain is present
  chain_count=$(echo "$output" | grep -c "BEGIN CERTIFICATE")
  subject=$(echo "$output" | grep "subject=" | head -1 | sed 's/.*CN=//')

  if [ "$chain_count" -lt 2 ]; then
    echo -e "  ${YELLOW}⚠️  Certificate chain incomplete (${chain_count} certs)${NC}"
  else
    echo -e "  ${GREEN}✅ Certificate chain OK (${chain_count} certs)${NC}"
  fi

  # Display CN and Issuer for first cert
  issuer=$(echo "$output" | grep "issuer=" | head -1 | sed 's/.*CN=//')
  echo "  Subject CN: $subject"
  echo "  Issuer CN:  $issuer"

  # Check expiration
  expiry_date=$(echo "$output" | openssl x509 -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
  echo "  Expires: $expiry_date"
  echo ""
done

echo "-------------------------------------------------------------"
echo "✅ Certificate verification complete."
echo ""
