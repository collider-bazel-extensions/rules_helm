"""Bzlmod extension. One `version` tag class — fetches the helm tarball
for each supported platform.

Same shape as rules_opa: per-platform repos named `helm_<plat>` each
contain just the helm binary. The toolchain at //toolchain:helm selects
the right one based on the resolved exec/target platform.
"""

load("//private:repositories.bzl", "helm_binary_repo")
load("//private:versions.bzl", "DEFAULT_VERSION", "HELM_VERSIONS", "PLATFORMS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _select_version(mctx):
    """The one Helm version to fetch.

    The extension runs once for the whole build and sees every module's
    tags, but the repos it creates (`helm_<plat>`) are global, so it must
    pick a single version and create each repo once. The root module's
    `helm.version()` wins; without one, rules_helm's own (from its
    MODULE.bazel, which imports these repos and registers their
    toolchains for every consumer); without that, DEFAULT_VERSION. Other
    modules' tags are ignored.
    """
    root = []
    own = []
    for mod in mctx.modules:
        versions = [tag.version for tag in mod.tags.version]
        if mod.is_root:
            root = versions
        elif mod.name == "rules_helm":
            own = versions
    for candidates, who in [(root, "the root module"), (own, "rules_helm")]:
        distinct = sorted({v: None for v in candidates}.keys())
        if len(distinct) > 1:
            fail("rules_helm: {} sets helm.version() to more than one version ({}); set one.".format(
                who,
                ", ".join(distinct),
            ))
        if distinct:
            return distinct[0]
    return DEFAULT_VERSION

def _impl(mctx):
    version = _select_version(mctx)
    if version not in HELM_VERSIONS:
        fail("rules_helm: helm.version(version = \"{}\") is not supported. Supported: {}".format(
            version,
            ", ".join(sorted(HELM_VERSIONS.keys())),
        ))
    for plat in PLATFORMS.keys():
        helm_binary_repo(
            name     = "helm_" + plat,
            version  = version,
            platform = plat,
        )

helm = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
