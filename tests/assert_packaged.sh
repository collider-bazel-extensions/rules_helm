#!/usr/bin/env bash
# Assertion harness for tests/example_package. Verifies:
#   1. The .tgz exists and is a valid gzip+tar.
#   2. It contains the expected chart files (Chart.yaml, values.yaml,
#      templates/*).
#   3. Every entry's mtime is 0 — proves the determinism re-pack
#      happened (helm package's own output uses wall-clock mtimes).
set -euo pipefail

TGZ="${1:?usage: $0 <chart.tgz>}"
[[ -f "$TGZ" ]] || { echo "package not found: $TGZ" >&2; exit 1; }

# 1. tar -tzf must succeed.
if ! tar -tzf "$TGZ" >/dev/null; then
  echo "assert_packaged: tar -tzf failed on $TGZ" >&2
  exit 1
fi

# 2. expected entries.
listing=$(tar -tzf "$TGZ" | sort)
failed=0
must_list() {
  local needle="$1"
  if ! grep -qx -- "$needle" <<<"$listing"; then
    echo "assert_packaged: missing entry '${needle}' in tarball" >&2
    failed=1
  fi
}
must_list "example/"
must_list "example/Chart.yaml"
must_list "example/values.yaml"
must_list "example/templates/deployment.yaml"
must_list "example/templates/service.yaml"

# 3. all mtimes are 0. tar's `-vt` shows the date/time per entry; 0 means
# 1970-01-01 00:00. Easier check: tar --to-command='echo $TAR_MTIME' or
# just look at the verbose listing for "1970-01-01" on every line.
nonzero=$(tar -tvzf "$TGZ" | awk '$0 !~ /1970-01-01/ {print}')
if [[ -n "$nonzero" ]]; then
  echo "assert_packaged: found entries with non-zero mtime (re-pack didn't normalize):" >&2
  echo "$nonzero" >&2
  failed=1
fi

if (( failed )); then
  echo "---- listing ----" >&2
  tar -tvzf "$TGZ" >&2
  exit 1
fi

echo "assert_packaged: OK"
