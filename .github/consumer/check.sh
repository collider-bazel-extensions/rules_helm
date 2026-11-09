#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no helm.version() in the root resolves, and a helm_template renders
#      with the default version
#   2. the same version set twice in the root resolves; a root's other
#      supported version wins over rules_helm's
#   3. an unsupported version fails, naming helm.version
#   4. @rules_helm//... loads (tests/ is not shipped)
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_helm"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
if [[ -e "$src/tests" ]]; then echo "FAIL: archive contains tests/" >&2; exit 1; fi
default_version="$(sed -n 's/^DEFAULT_VERSION = "\(.*\)"$/\1/p' "$src/private/versions.bzl")"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cp -r "$repo/tests/example_chart" "$c/chart"
    cat > "$c/chart/BUILD.bazel" <<'BUILD'
filegroup(
    name = "files",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)
BUILD
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_helm")
local_path_override(module_name = "rules_helm", path = "$src")
$2
MOD
    cat > "$c/BUILD.bazel" <<'BUILD'
load("@rules_helm//:defs.bzl", "helm_template")

helm_template(
    name = "render",
    chart = ["//chart:files"],
    release_name = "smoke",
)
BUILD
    echo "$c"
}

# 1. No helm.version(): resolves; the registered toolchain's helm renders.
c="$(consumer untagged "")"
(cd "$c" && bazel mod deps >/dev/null)
(cd "$c" && bazel build //:render)
"$(cd "$c" && bazel info output_base)/external/rules_helm++helm+helm_linux_amd64/helm" version --short | tee "$work/untagged.out"
grep -q "^v$default_version+" "$work/untagged.out" || { echo "FAIL: untagged consumer did not get helm $default_version" >&2; exit 1; }
echo "PASS: untagged root resolves, helm $default_version"

# 2. The same version twice in the root.
c="$(consumer twice "helm = use_extension(\"@rules_helm//:extensions.bzl\", \"helm\")
helm.version(version = \"$default_version\")
helm.version(version = \"$default_version\")")"
(cd "$c" && bazel mod deps >/dev/null)
echo "PASS: repeated identical helm.version resolves"

# 2b. A root's own (supported, non-default) version wins over rules_helm's.
other="$(sed -n 's/^    "\([0-9][0-9.]*\)": {$/\1/p' "$src/private/versions.bzl" | grep -vx "$default_version" | head -1)"
if [[ -n "$other" ]]; then
    c="$(consumer other "helm = use_extension(\"@rules_helm//:extensions.bzl\", \"helm\")
helm.version(version = \"$other\")")"
    (cd "$c" && bazel build //:render)
    "$(cd "$c" && bazel info output_base)/external/rules_helm++helm+helm_linux_amd64/helm" version --short | tee "$work/other.out"
    grep -q "^v$other+" "$work/other.out" || { echo "FAIL: root's helm.version($other) did not win" >&2; exit 1; }
    echo "PASS: root's helm.version($other) wins"
fi

# 3. An unsupported version fails with a message naming helm.version.
c="$(consumer unsupported 'helm = use_extension("@rules_helm//:extensions.bzl", "helm")
helm.version(version = "0.0.1")')"
if (cd "$c" && bazel mod deps) > "$work/unsupported.out" 2>&1; then
    echo "FAIL: unsupported version resolved" >&2; exit 1
fi
grep -q 'helm.version(version = "0.0.1") is not supported' "$work/unsupported.out" || {
    cat "$work/unsupported.out" >&2; echo "FAIL: unsupported version: wrong error" >&2; exit 1; }
echo "PASS: unsupported version fails clearly"

# 4. //... loads.
(cd "$work/untagged" && bazel query @rules_helm//... >/dev/null)
echo "PASS: @rules_helm//... loads"
