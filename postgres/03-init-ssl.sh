#!/bin/bash
set -e

SSL_DIR="/var/lib/postgresql/data/certs"
SSL_SERVER_CRT="$SSL_DIR/server.crt"
SSL_SERVER_KEY="$SSL_DIR/server.key"
SSL_SERVER_CSR="$SSL_DIR/server.csr"

SSL_ROOT_KEY="$SSL_DIR/root.key"
SSL_ROOT_CRT="$SSL_DIR/root.crt"
SSL_V3_EXT="$SSL_DIR/v3.ext"

POSTGRES_CONF="$PGDATA/postgresql.conf"

# create and chown
mkdir -p "$SSL_DIR"
chown postgres:postgres "$SSL_DIR"

# generate root CA
openssl req -new -x509 -days "${SSL_CERT_DAYS:-820}" -nodes -text \
  -out "$SSL_ROOT_CRT" -keyout "$SSL_ROOT_KEY" \
  -subj "/CN=root-ca"
chmod og-rwx "$SSL_ROOT_KEY"

# server CSR/key
openssl req -new -nodes -text \
  -out "$SSL_SERVER_CSR" -keyout "$SSL_SERVER_KEY" \
  -subj "/CN=localhost"
chown postgres:postgres "$SSL_SERVER_KEY"
chmod og-rwx "$SSL_SERVER_KEY"

# v3 extensions
cat >| "$SSL_V3_EXT" <<EOF
[v3_req]
authorityKeyIdentifier = keyid, issuer
basicConstraints = critical, CA:TRUE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:localhost
EOF

# sign server cert
openssl x509 -req -in "$SSL_SERVER_CSR" -extfile "$SSL_V3_EXT" -extensions v3_req \
  -text -days "${SSL_CERT_DAYS:-820}" \
  -CA "$SSL_ROOT_CRT" -CAkey "$SSL_ROOT_KEY" -CAcreateserial \
  -out "$SSL_SERVER_CRT"
chown postgres:postgres "$SSL_SERVER_CRT"

# enable SSL in Postgres conf
cat >> "$POSTGRES_CONF" <<EOF
ssl = on
ssl_cert_file = '$SSL_SERVER_CRT'
ssl_key_file  = '$SSL_SERVER_KEY'
ssl_ca_file   = '$SSL_ROOT_CRT'
EOF
