"""helm_toolchain — exposes the platform-resolved helm binary as a
`ToolchainInfo` so consumer rules can resolve it via `ctx.toolchains[...]`
without depending on the binary's specific path.
"""

load("//private:providers.bzl", "HelmInfo")

HELM_TOOLCHAIN_TYPE = Label("//toolchain:helm")

def _toolchain_impl(ctx):
    info = HelmInfo(
        version  = ctx.attr.version,
        helm_bin = ctx.file.helm_bin,
    )
    return [
        platform_common.ToolchainInfo(helm = info),
        DefaultInfo(
            files    = depset([ctx.file.helm_bin]),
            runfiles = ctx.runfiles(files = [ctx.file.helm_bin]),
        ),
    ]

helm_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "helm_bin": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The platform-specific helm executable.",
        ),
    },
)
