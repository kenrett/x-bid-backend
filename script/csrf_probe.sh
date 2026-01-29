#!/usr/bin/env bash
set -euo pipefail

origin="https://www.biddersweet.app"
url="https://api.biddersweet.app/api/v1/csrf"
workdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
response_file="${workdir}/csrf_probe_response.txt"
cookie_jar="${workdir}/csrf_probe_cookies.txt"

curl -sS -i \
  -H "Origin: ${origin}" \
  -H "Accept: application/json" \
  -H "X-Storefront-Key: main" \
  -c "${cookie_jar}" \
  -b "${cookie_jar}" \
  "${url}" \
  > "${response_file}"

cat "${response_file}"

echo
if command -v rg >/dev/null 2>&1; then
  header_match() { rg -n "^Set-Cookie:.*csrf_token" "${response_file}" >/dev/null; }
  body_match() { rg -n '"csrf_token"' "${response_file}" >/dev/null; }
else
  header_match() { grep -n "^Set-Cookie:.*csrf_token" "${response_file}" >/dev/null; }
  body_match() { grep -n '"csrf_token"' "${response_file}" >/dev/null; }
fi

if header_match; then
  echo "Set-Cookie: csrf_token present"
else
  echo "Set-Cookie: csrf_token NOT present"
fi

if body_match; then
  echo "Body includes csrf_token"
else
  echo "Body missing csrf_token"
fi
