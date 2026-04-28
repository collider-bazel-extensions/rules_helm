"""Bzlmod extension. One `version` tag class — fetches the helm tarball
for each supported platform.

Same shape as rules_opa: per-platform repos named `helm_<plat>` each
contain just the helm binary. The toolchain at //toolchain:helm selects
the right one based on the resolved exec/target platform.
"""

load("//private:repositories.bzl", "helm_binary_repo")
load("//private:versions.bzl", "PLATFORMS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    # Only honor `version` tags from the root module. Without this guard,
    # both rules_helm (when consumed as a dep) and the consumer would each
    # emit `@helm_<plat>` repos and Bazel would collide them. The library's
    # own MODULE.bazel still needs `helm.version(...)` so its in-tree
    # tests can build, but that only fires when rules_helm itself is the
    # root.
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            for plat in PLATFORMS.keys():
                helm_binary_repo(
                    name     = "helm_" + plat,
                    version  = tag.version,
                    platform = plat,
                )

helm = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
