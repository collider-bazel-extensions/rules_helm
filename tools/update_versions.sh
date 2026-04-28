#!/usr/bin/env bash
# tools/update_versions.sh — refresh HELM_VERSIONS in private/versions.bzl.
#
# Usage:
#     bash tools/update_versions.sh <version>            # add or update entry
#     bash tools/update_versions.sh <version> --update   # also auto-edit
#                                                        # private/versions.bzl
#
# Helm publishes per-platform tarballs at https://get.helm.sh/ with
# matching `.tar.gz.sha256sum` companions. Each tarball extracts to a
# `<plat>/helm` subdirectory.
set -euo pipefail

VERSION="${1:?usage: tools/update_versions.sh <version> [--update]}"
UPDATE=0
[[ "${2:-}" == "--update" ]] && UPDATE=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSIONS_BZL="$REPO_ROOT/private/versions.bzl"

declare -A SHA
for plat in linux-amd64 darwin-amd64 darwin-arm64; do
    url="https://get.helm.sh/helm-v${VERSION}-${plat}.tar.gz.sha256sum"
    sha=$(curl -fsSL "$url" | awk '{print $1}')
    SHA[$plat]="$sha"
    echo "[update_versions] helm-v${VERSION}-${plat}.tar.gz: $sha"
done

if (( UPDATE )); then
    echo
    echo "[update_versions] updating $VERSIONS_BZL"
    python3 - "$VERSIONS_BZL" "$VERSION" \
        "${SHA[linux-amd64]}" "${SHA[darwin-amd64]}" "${SHA[darwin-arm64]}" <<'PY'
import re, sys
path, version, l, da, dr = sys.argv[1:6]
src = open(path).read()
m = re.search(r"(HELM_VERSIONS\s*=\s*\{)([\s\S]*?)(\n\})", src)
if not m:
    sys.exit("could not locate HELM_VERSIONS dict in versions.bzl")
head, body, tail = m.group(1), m.group(2), m.group(3)
entry = (
    f'\n    "{version}": {{\n'
    f'        "linux_amd64": {{\n'
    f'            "url":    "https://get.helm.sh/helm-v{version}-linux-amd64.tar.gz",\n'
    f'            "sha256": "{l}",\n'
    f'            "strip":  "linux-amd64",\n'
    f'        }},\n'
    f'        "darwin_amd64": {{\n'
    f'            "url":    "https://get.helm.sh/helm-v{version}-darwin-amd64.tar.gz",\n'
    f'            "sha256": "{da}",\n'
    f'            "strip":  "darwin-amd64",\n'
    f'        }},\n'
    f'        "darwin_arm64": {{\n'
    f'            "url":    "https://get.helm.sh/helm-v{version}-darwin-arm64.tar.gz",\n'
    f'            "sha256": "{dr}",\n'
    f'            "strip":  "darwin-arm64",\n'
    f'        }},\n'
    f'    }},'
)
existing = re.search(rf'\n    "{re.escape(version)}":[\s\S]*?\n    \}},', body)
new_body = (body[:existing.start()] + entry + body[existing.end():]) if existing else (body.rstrip(",\n ") + "," + entry)
new_src = src[:m.start()] + head + new_body + tail + src[m.end():]
open(path, "w").write(new_src)
print(f"  wrote HELM_VERSIONS['{version}']")
PY
    echo
    echo "Next: bump MODULE.bazel's \`helm.version(version = \"$VERSION\")\` if you"
    echo "      want this to be the default, then run \`bazel test //tests:...\`."
else
    echo
    echo "Next steps (re-run with --update to do this automatically):"
    echo "  1. Add or update in private/versions.bzl::HELM_VERSIONS[\"$VERSION\"]"
    echo "     with the SHAs printed above."
    echo "  2. Bump MODULE.bazel's \`helm.version(version = \"$VERSION\")\`."
fi
