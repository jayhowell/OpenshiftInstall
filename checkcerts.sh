#!/usr/bin/env bash
#
# check_redhat_cert_issuer.sh
# Verify that Red Hat and Quay endpoints present a certificate issued by Amazon, not Forcepoint
#
# Usage: ./check_redhat_cert_issuer.sh
#

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

# Expected issuer keyword
EXPECTED="Amazon"
BAD_ISSUER="Forcepoint"

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

echo "🔍 Checking SSL certificate issuers for Red Hat and Quay endpoints..."
echo "-------------------------------------------------------------"
echo ""

for host in "${HOSTS[@]}"; do
  echo "🟢 Checking ${host}:443 ..."
  output=$(timeout 10 openssl s_client -connect "${host}:443" -servername "${host}" -showcerts </dev/null 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo -e "  ${RED}❌ Connection failed or timed out${NC}"
    echo ""
    continue
  fi

  # Extract issuer CN
  issuer=$(echo "$output" | grep "issuer=" | head -1 | sed 's/.*CN=//')

  if echo "$issuer" | grep -qi "$BAD_ISSUER"; then
    echo -e "  ${RED}⚠️  CERT REWRITTEN by Forcepoint!${NC}"
    echo "  Issuer: $issuer"
  elif echo "$issuer" | grep -qi "$EXPECTED"; then
    echo -e "  ${GREEN}✅ OK - Issuer is Amazon (${issuer})${NC}"
  else
    echo -e "  ${YELLOW}❓ Unexpected issuer${NC}"
    echo "  Issuer: $issuer"
  fi

  # Optional: show expiration date
  expiry=$(echo "$output" | openssl x509 -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
  echo "  Expires: $expiry"
  echo ""
done

echo "-------------------------------------------------------------"
echo "✅ Certificate issuer verification complete."
echo ""

