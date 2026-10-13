#!/usr/bin/env bash
set -euo pipefail

url="${PHOTO_URL:-http://127.0.0.1/whoami}"
samples=()
for ((i = 1; i <= 30; i++)); do
  pod=$(curl --noproxy '*' --fail --silent --show-error --max-time 5 \
    -H 'Host: photo.local' -H 'Connection: close' "$url")
  printf '%02d %s\n' "$i" "$pod"
  samples+=("$pod")
done
printf '\nRequêtes par Pod :\n'
printf '%s\n' "${samples[@]}" | sort | uniq -c
count=$(printf '%s\n' "${samples[@]}" | sort -u | wc -l)
if ((count != 3)); then
  printf 'Attendu : 3 Pods distincts ; observé : %s. Vérifier les Pods Ready et les EndpointSlices.\n' "$count" >&2
  exit 1
fi
printf 'Validation réussie : les 3 Pods ont répondu via l’Ingress.\n'
