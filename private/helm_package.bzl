"""helm_package — Bazel action rule that produces a chart archive
(`.tgz`) from a chart directory.

Wraps `helm package <chart-dir> -d <tmpdir>`, then re-packs the resulting
tarball with normalized metadata (mtime=0, sorted entries, stripped
owner/group) so the output is deterministic across builds. `helm package`
on its own embeds wall-clock mtimes in the inner tar and a timestamp in
the gzip header, which makes the bytes non-reproducible.

Output: a single file `<name>.tgz` regardless of the chart name/version
in `Chart.yaml`. Consumers that need the canonical `<chartname>-<version>.tgz`
filename can rename via `genrule` or pass through `pkg_tar`.
"""

def _sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:helm"]
    helm = tc.helm.helm_bin

    # See helm_template's notes: pick the shallowest Chart.yaml as the
    # chart root so subchart Chart.yamls (under charts/<sub>/) don't
    # confuse the rule.
    chart_yaml = None
    for f in ctx.files.chart:
        if f.basename != "Chart.yaml":
            continue
        if chart_yaml == None or f.path.count("/") < chart_yaml.path.count("/"):
            chart_yaml = f
    if chart_yaml == None:
        fail("helm_package {}: chart attr must include a Chart.yaml file".format(ctx.label))
    chart_root = chart_yaml.dirname

    out = ctx.actions.declare_file(ctx.label.name + ".tgz")

    helm_args = [helm.path, "package", chart_root, "-d", "."]
    if ctx.attr.chart_version:
        helm_args.extend(["--version", ctx.attr.chart_version])
    if ctx.attr.app_version:
        helm_args.extend(["--app-version", ctx.attr.app_version])
    helm_args.extend(ctx.attr.helm_package_args)

    helm_cmd = " ".join([_sh_quote(a) for a in helm_args])

    # Determinism re-pack:
    # 1. helm package writes <chartname>-<version>.tgz into the action's
    #    cwd (which is the sandbox root in Bazel).
    # 2. We don't know the exact filename at analysis time (depends on
    #    Chart.yaml contents), so glob for the only *.tgz in cwd.
    # 3. Decompress; re-tar with --mtime='@0' --sort=name --owner=0
    #    --group=0 --numeric-owner; recompress with `gzip -n` (no
    #    timestamp/filename in the gzip header).
    # 4. Move the result to the declared output path.
    cmd = """
set -euo pipefail
{helm_cmd} >/dev/null
pkg=$(echo *.tgz)
[[ -f "$pkg" ]] || {{ echo "helm_package: helm did not produce a .tgz" >&2; exit 1; }}
mkdir -p .repack
cd .repack
tar -xzf "../$pkg"
# Top-level entry inside the helm tarball is the chart directory.
top=$(ls -1 | head -1)
tar --mtime='@0' --sort=name --owner=0 --group=0 --numeric-owner \
    -cf - "$top" \
  | gzip -n -9 > {out}
""".format(
        helm_cmd = helm_cmd,
        out = _sh_quote("../" + out.path),
    )

    ctx.actions.run_shell(
        outputs = [out],
        inputs  = depset(ctx.files.chart + [helm]),
        command = cmd,
        mnemonic = "HelmPackage",
        progress_message = "Packaging helm chart %{label}",
    )

    return [DefaultInfo(files = depset([out]))]

helm_package = rule(
    implementation = _impl,
    attrs = {
        "chart": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "All files comprising the helm chart, including " +
                  "`Chart.yaml`. Same shape as `helm_template.chart`.",
        ),
        "chart_version": attr.string(
            doc = "Sets `--version`. Overrides the version field in " +
                  "Chart.yaml. Useful for stamping CI builds.",
        ),
        "app_version": attr.string(
            doc = "Sets `--app-version`. Overrides the appVersion field " +
                  "in Chart.yaml.",
        ),
        "helm_package_args": attr.string_list(
            doc = "Extra args passed verbatim to `helm package`, after " +
                  "all attribute-derived flags.",
        ),
    },
    toolchains = ["//toolchain:helm"],
)
