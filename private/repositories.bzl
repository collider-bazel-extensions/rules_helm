"""Per-platform binary repo. Downloads + extracts the helm tarball for one
platform, exposes the binary as `:bin`, and emits a fully-formed
`helm_toolchain` + `toolchain` declaration so consumers can register the
toolchain directly without rules_helm having to hardcode the version.
"""

load(":versions.bzl", "HELM_VERSIONS", "PLATFORMS")

_BUILD_TMPL = """\
load("@rules_helm//toolchain:toolchain.bzl", "helm_toolchain")

package(default_visibility = ["//visibility:public"])

# Filegroup name MUST differ from the binary file name "helm" — bare
# `srcs = ["helm"]` would otherwise resolve to the filegroup itself and
# trigger a self-edge cycle. Same lesson rules_kind / rules_opa learned.
filegroup(
    name = "bin",
    srcs = ["helm"],
)

helm_toolchain(
    name     = "toolchain_impl",
    version  = "{version}",
    helm_bin = ":bin",
)

# The toolchain declaration that consumers register. Each per-platform
# repo emits its own so HelmInfo.version reflects the version actually
# fetched by `helm.version()` at module-extension time, instead of being
# pinned to whatever happened to be hardcoded in //toolchain:BUILD.bazel.
toolchain(
    name = "toolchain",
    toolchain_type         = "@rules_helm//toolchain:helm",
    exec_compatible_with   = {compat},
    target_compatible_with = {compat},
    toolchain              = ":toolchain_impl",
)
"""

def _impl(rctx):
    version = rctx.attr.version
    platform = rctx.attr.platform
    if version not in HELM_VERSIONS:
        fail("rules_helm: unknown version '{}'. Known: {}".format(
            version,
            sorted(HELM_VERSIONS.keys()),
        ))
    plats = HELM_VERSIONS[version]
    if platform not in plats:
        fail("rules_helm: version {} has no entry for platform '{}'. Have: {}".format(
            version, platform, sorted(plats.keys()),
        ))
    info = plats[platform]
    rctx.download_and_extract(
        url        = info["url"],
        sha256     = info["sha256"],
        # The tarball extracts to `<strip>/helm` (e.g. `linux-amd64/helm`);
        # strip_prefix lifts the binary to the top of the repo so the
        # filegroup can reference it as plain `"helm"` regardless of
        # platform.
        stripPrefix = info["strip"],
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD_TMPL.format(
        version = version,
        compat = repr(PLATFORMS[platform]),
    ))

helm_binary_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "version":  attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
    },
)
