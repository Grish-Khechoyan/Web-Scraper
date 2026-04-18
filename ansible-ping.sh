#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Keep Ansible temp files in writable locations.
export ANSIBLE_LOCAL_TEMP=/tmp/ansible-local
export ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote
mkdir -p "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_REMOTE_TEMP"

echo "Starting Project Genesis stack..."
docker-compose up -d

BACKEND_ID="$(docker-compose ps -q backend)"
DB_ID="$(docker-compose ps -q db)"

if [[ -z "$BACKEND_ID" || -z "$DB_ID" ]]; then
  echo "Could not detect backend/db containers from docker-compose."
  exit 1
fi

BACKEND_NAME="$(docker inspect --format '{{.Name}}' "$BACKEND_ID" | sed 's#^/##')"
DB_NAME="$(docker inspect --format '{{.Name}}' "$DB_ID" | sed 's#^/##')"

cat > inventory.yml <<EOF
all:
  children:
    backend:
      hosts:
        ${BACKEND_NAME}:
          ansible_connection: docker
          ansible_python_interpreter: /usr/local/bin/python
    database:
      hosts:
        ${DB_NAME}:
          ansible_connection: docker
EOF

echo
echo "Running containers:"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | sed -n '1p;/webscraper-/p'

echo
echo "Generated inventory.yml:"
cat inventory.yml

echo
echo "Pinging backend with Ansible ping module..."
ansible backend -i inventory.yml -m ping

echo
echo "Checking db container with Ansible raw module (Postgres image has no Python by default)..."
ansible database -i inventory.yml -m raw -a "echo db-container-reachable"

echo
echo "All checks completed."
