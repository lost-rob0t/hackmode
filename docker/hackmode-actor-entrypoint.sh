#!/bin/sh
# Entrypoint for the Hackmode actor service container.
#
# Loads secret-bearing environment variables from *_FILE mounts, prepares
# the durable operation database directory, and drops to the non-root actor
# uid before execing the saved executable.
set -eu

load_secret() {
  var="$1"
  file_var="${1}_FILE"
  if [ -z "$(eval "echo \${$var:-}")" ] && [ -n "$(eval "echo \${$file_var:-}")" ]; then
    eval "export \"$var=\$(cat \"\$${file_var}\")\""
  fi
}

load_secret STARINTEL_API_KEY
load_secret HACKMODE_STARINTEL_API_KEY

mkdir -p /var/lib/hackmode
chown -R 10001:10001 /var/lib/hackmode 2>/dev/null || true

exec su-exec 10001:10001 /bin/hackmode-actor-service
