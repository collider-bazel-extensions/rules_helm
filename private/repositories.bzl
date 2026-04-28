"""Per-platform binary repo. Downloads + extracts the helm tarball for one
platform, exposes the binary at the top-level path `helm`.
"""

load(":versions.bzl", "HELM_VERSIONS")

_BUILD_TMPL = """\
package(default_visibility = ["//visibility:public"])

# Filegroup name MUST differ from the binary file name "helm" — bare
# `srcs = ["helm"]` would otherwise resolve to the filegroup itself and
# trigger a self-edge cycle. Same lesson rules_kind / rules_opa learned.
filegroup(
    name = "bin",
    srcs = ["helm"],
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
    rctx.file("BUILD.bazel", _BUILD_TMPL)

helm_binary_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "version":  attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
    },
)
