#!/usr/bin/env bash
set -euo pipefail

# Compatibilité: lire DB_* ou POSTGRES_* et définir les POSTGRES_* attendues par nos commandes
: "${POSTGRES_USER:=${DB_USER:-postgres}}"
: "${POSTGRES_PASSWORD:=${DB_PASSWORD:-postgres}}"
: "${POSTGRES_DB:=${DB_NAME:-postgres}}"
: "${PGDATA:=/var/lib/postgresql/data}"

export PATH="/usr/lib/postgresql/13/bin:$PATH"

echo "[postgres-db] Using:"
echo "  PGDATA=$PGDATA"
echo "  POSTGRES_USER=$POSTGRES_USER"
echo "  POSTGRES_DB=$POSTGRES_DB"

# Initialisation si première exécution
if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
  echo "[postgres-db] initdb…"
  install -d -m 0700 -o postgres -g postgres "$PGDATA"

  # initdb avec mot de passe (non interactif) et scram-sha-256
  pwfile="$(mktemp)"
  printf "%s" "$POSTGRES_PASSWORD" > "$pwfile"
  initdb -D "$PGDATA" -U "$POSTGRES_USER" -A scram-sha-256 --pwfile="$pwfile"
  rm -f "$pwfile"

  # Écoute réseau
  echo "listen_addresses = '*'" >> "$PGDATA/postgresql.conf"

  # Auth: autoriser md5/scram pour tout le cluster (contexte labo)
  echo "host all all 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
  echo "host all all ::/0      scram-sha-256" >> "$PGDATA/pg_hba.conf"

  # Démarrer temporairement pour créer la BDD si besoin
  pg_ctl -D "$PGDATA" -o "-c listen_addresses='localhost'" -w start

  if [[ "$POSTGRES_DB" != "postgres" ]]; then
    echo "[postgres-db] creating database '$POSTGRES_DB' owned by '$POSTGRES_USER'…"
    createdb -O "$POSTGRES_USER" "$POSTGRES_DB" || true
  fi

  # Arrêt propre du bootstrap
  pg_ctl -D "$PGDATA" -m fast -w stop
fi

echo "[postgres-db] starting postgres…"
# Premier plan: c'est le process PID 1
exec postgres -D "$PGDATA" -c listen_addresses='*'
