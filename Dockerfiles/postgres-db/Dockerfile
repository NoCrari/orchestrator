FROM debian:bullseye

RUN apt-get update && apt-get install -y postgresql-13 postgresql-contrib

USER postgres

RUN rm -rf /var/lib/postgresql/13/main

COPY tools/setup_db.sh /tmp/setup_db.sh


ENTRYPOINT [ "bash", "/tmp/setup_db.sh" ]
FROM debian:bullseye

# Postgres 13 + outils, sans recommandations pour rester léger
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    postgresql-13 postgresql-contrib ca-certificates bash \
    && rm -rf /var/lib/apt/lists/*

# Data dir commun monté depuis le PV
ENV PGDATA=/var/lib/postgresql/data

# Préparer le dossier de données (le vrai init se fait au runtime)
RUN mkdir -p "$PGDATA" && chown -R postgres:postgres /var/lib/postgresql

# Script d'init/launch
COPY tools/setup_db.sh /tmp/setup_db.sh
RUN chmod +x /tmp/setup_db.sh && chown postgres:postgres /tmp/setup_db.sh

USER postgres

# Port Postgres
EXPOSE 5432

# Lancement via notre script (init si nécessaire, puis "exec postgres -D …")
ENTRYPOINT [ "bash", "/tmp/setup_db.sh" ]
