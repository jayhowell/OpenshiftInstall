#!/usr/bin/env bash
#
# check_redhat_cert_issuer_multi.sh
# Verify that Red Hat and Quay endpoints present certificates issued by known trusted CAs
# Detects rewritten certs (e.g., Forcepoint)
#
# Usage: ./check_redhat_cert_issuer_multi.sh
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

# List of expected issuers (patterns are matched case-insensitively)
ALLOWED_ISSUERS=(
  "Amazon"
  "DigiCert Global G3 TLS ECC SHA384 2020 CA1"
  "DigiCert TLS RSA SHA256 2020 CA1"
  "Red Hat Entitlement Operations Authority"
  "GeoTrust TLS RSA CA G1"
  "R12"
)

# Known bad issuers (proxies, interceptors, etc.)
BAD_ISSUERS=(
  "Forcepoint"
)

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

  matched_good=false
  matched_bad=false

  for bad in "${BAD_ISSUERS[@]}"; do
    if echo "$issuer" | grep -qi "$bad"; then
      matched_bad=true
      break
    fi
  done

  if [ "$matched_bad" = true ]; then
    echo -e "  ${RED}⚠️  CERT REWRITTEN by Forcepoint or untrusted proxy!${NC}"
    echo "  Issuer: $issuer"
  else
    for good in "${ALLOWED_ISSUERS[@]}"; do
      if echo "$issuer" | grep -qi "$good"; then
        matched_good=true
        break
      fi
    done

    if [ "$matched_good" = true ]; then
      echo -e "  ${GREEN}✅ OK - Trusted issuer detected (${issuer})${NC}"
    else
      echo -e "  ${YELLOW}❓ Unexpected issuer${NC}"
      echo "  Issuer: $issuer"
    fi
  fi

  # Optional: show expiration date
  expiry=$(echo "$output" | openssl x509 -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
  echo "  Expires: $expiry"
  echo ""
done

echo "-------------------------------------------------------------"
echo "✅ Certificate issuer verification complete."
echo ""

