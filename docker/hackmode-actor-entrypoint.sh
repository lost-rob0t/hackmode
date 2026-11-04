#!/bin/sh
# Entrypoint for the Hackmode actor service container.
#
# The image starts as uid 10001 (hackmode); this script only fills
# secret-bearing environment variables from *_FILE mounts and execs the
# saved executable.
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

exec /bin/hackmode-actor-service
