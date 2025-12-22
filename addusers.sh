#!/usr/bin/env bash
set -euo pipefail

# ====== DEFAULTS ======
SECRET_NAME="htpass-secret"
NAMESPACE="openshift-config"
OAUTH_NAME="cluster"
TMP_DIR="$(mktemp -d)"

# ====== ARG PARSING ======
USERNAME=""
PASSWORD=""

usage() {
  echo "Usage: $0 --user <username> --password <password>"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USERNAME="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "${USERNAME}" || -z "${PASSWORD}" ]]; then
  usage
fi

# ====== PRECHECKS ======
command -v oc >/dev/null 2>&1 || { echo "ERROR: oc not found"; exit 1; }
command -v htpasswd >/dev/null 2>&1 || { echo "ERROR: htpasswd not found (install httpd-tools)"; exit 1; }

echo "Verifying cluster access..."
oc whoami >/dev/null

# ====== FETCH EXISTING HTPASSWD (IF ANY) ======
HTPASSWD_FILE="${TMP_DIR}/users.htpasswd"

if oc get secret "${SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Existing htpasswd secret found. Preserving users..."
  oc get secret "${SECRET_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.data.htpasswd}' | base64 -d > "${HTPASSWD_FILE}"
else
  echo "No existing htpasswd secret found. Creating new one..."
  touch "${HTPASSWD_FILE}"
fi

# ====== ADD OR UPDATE USER ======
if grep -q "^${USERNAME}:" "${HTPASSWD_FILE}"; then
  echo "User '${USERNAME}' already exists. Updating password..."
  htpasswd -B -b "${HTPASSWD_FILE}" "${USERNAME}" "${PASSWORD}"
else
  echo "Adding new user '${USERNAME}'..."
  htpasswd -B -b "${HTPASSWD_FILE}" "${USERNAME}" "${PASSWORD}"
fi

# ====== UPDATE SECRET ======
if oc get secret "${SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  oc delete secret "${SECRET_NAME}" -n "${NAMESPACE}"
fi

oc create secret generic "${SECRET_NAME}" \
  --from-file=htpasswd="${HTPASSWD_FILE}" \
  -n "${NAMESPACE}"

# ====== CONFIGURE OAUTH (IDEMPOTENT) ======
echo "Ensuring OAuth is configured..."

cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: ${OAUTH_NAME}
spec:
  identityProviders:
  - name: htpasswd
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: ${SECRET_NAME}
EOF

# ====== GRANT CLUSTER ADMIN ======
echo "Granting cluster-admin role to '${USERNAME}'..."
oc adm policy add-cluster-role-to-user cluster-admin "${USERNAME}" || true

# ====== CLEANUP ======
rm -rf "${TMP_DIR}"

echo
echo "SUCCESS"
echo "User '${USERNAME}' is configured and has cluster-admin privileges."
echo "Login via the OpenShift console using the 'htpasswd' provider."

