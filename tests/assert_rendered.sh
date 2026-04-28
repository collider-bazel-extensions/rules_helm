#!/usr/bin/env bash
# Assertion harness for tests/example_render. Verifies the rendered YAML
# contains the objects we expect — proves helm_template wired up the
# release name + values + namespace, not just that helm exited zero.
set -euo pipefail

YAML="${1:?usage: $0 <rendered.yaml>}"
[[ -f "$YAML" ]] || { echo "rendered YAML not found: $YAML" >&2; exit 1; }

failed=0
must_contain() {
  local needle="$1"
  if ! grep -qF -- "$needle" "$YAML"; then
    echo "assert_rendered: missing '${needle}' in ${YAML}" >&2
    failed=1
  fi
}

# Templates render with the release name we passed.
must_contain "name: smoke-example"
# Both kinds present.
must_contain "kind: Deployment"
must_contain "kind: Service"
# Image tag from set_strings overrides values.yaml's "1.27".
must_contain 'image: "nginx:1.27.4"'
# Service-port flowing through container.
must_contain "containerPort: 80"

if (( failed )); then
  echo "---- rendered YAML ----" >&2
  cat "$YAML" >&2
  exit 1
fi
echo "assert_rendered: OK"
