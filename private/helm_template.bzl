"""helm_template — Bazel action rule that renders a helm chart to a
single YAML file at build time.

Equivalent to running `helm template <release> <chart-dir> [flags...] > out.yaml`
on the host, but hermetic: the helm binary is the toolchain's, the chart
inputs are Bazel-tracked, and the output file is a declared action output.

The chart is expressed as a `label_list` containing every file in the
chart directory tree (Chart.yaml, values.yaml, templates/*.yaml,
charts/* subcharts, etc.). The rule finds Chart.yaml among them to
determine the chart root; everything else can sit anywhere relative to
that root.
"""

def _sh_quote(s):
    """Single-quote a string for safe shell interpolation."""
    return "'" + s.replace("'", "'\\''") + "'"

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:helm"]
    helm = tc.helm.helm_bin

    # Find the chart-root Chart.yaml. Charts may have subcharts under
    # `charts/<sub>/Chart.yaml`, so a single chart legitimately contains
    # multiple Chart.yaml files. Pick the one at the shallowest path
    # (fewest components in dirname) as the root; subcharts always live
    # deeper.
    chart_yaml = None
    for f in ctx.files.chart:
        if f.basename != "Chart.yaml":
            continue
        if chart_yaml == None or f.path.count("/") < chart_yaml.path.count("/"):
            chart_yaml = f
    if chart_yaml == None:
        fail("helm_template {}: chart attr must include a Chart.yaml file".format(ctx.label))
    chart_root = chart_yaml.dirname

    out = ctx.actions.declare_file(ctx.label.name + ".yaml")

    # Build the helm template invocation.
    release = ctx.attr.release_name if ctx.attr.release_name else ctx.label.name
    helm_args = [helm.path, "template", release, chart_root]

    if ctx.attr.namespace:
        helm_args.extend(["--namespace", ctx.attr.namespace])

    for vf in ctx.files.values:
        helm_args.extend(["-f", vf.path])

    # `set` and `set_strings` differ only in helm's interpretation:
    # `--set foo=1` parses 1 as int; `--set-string foo=1` keeps it as
    # string. Numeric image tags ("1.16.5") often need set-string to
    # avoid YAML coercion bugs.
    for k, v in ctx.attr.set.items():
        helm_args.extend(["--set", "{}={}".format(k, v)])
    for k, v in ctx.attr.set_strings.items():
        helm_args.extend(["--set-string", "{}={}".format(k, v)])

    if ctx.attr.kube_version:
        helm_args.extend(["--kube-version", ctx.attr.kube_version])
    for av in ctx.attr.api_versions:
        helm_args.extend(["--api-versions", av])
    if ctx.attr.include_crds:
        helm_args.append("--include-crds")
    helm_args.extend(ctx.attr.helm_template_args)

    # Action shape: a single shell command with stdout redirected to the
    # declared output. Each arg is single-quoted to defend against any
    # path or attr-string with spaces or shell metacharacters.
    cmd = " ".join([_sh_quote(a) for a in helm_args]) + " > " + _sh_quote(out.path)

    ctx.actions.run_shell(
        outputs   = [out],
        inputs    = depset(ctx.files.chart + ctx.files.values + [helm]),
        command   = cmd,
        mnemonic  = "HelmTemplate",
        progress_message = "Rendering helm chart %{label}",
    )

    return [DefaultInfo(files = depset([out]))]

helm_template = rule(
    implementation = _impl,
    attrs = {
        "chart": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "All files comprising the helm chart, including " +
                  "`Chart.yaml` (the rule scans for it to determine the " +
                  "chart root). Typically `glob(['my_chart/**'])`.",
        ),
        "values": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Values files, applied in order via `-f` (later files " +
                  "override earlier ones). Same semantics as host helm.",
        ),
        "set": attr.string_dict(
            doc = "Inline value overrides, applied as `--set key=value`. " +
                  "Helm parses values as YAML — e.g. '1' becomes int 1. " +
                  "Use `set_strings` to force string interpretation.",
        ),
        "set_strings": attr.string_dict(
            doc = "Inline value overrides, applied as `--set-string key=value`. " +
                  "Forces string interpretation; safe for image tags like " +
                  "'1.16.5' that would otherwise be parsed as floats.",
        ),
        "namespace": attr.string(
            doc = "Sets `--namespace`. Hard-coded namespaces in the chart " +
                  "templates take precedence over this; it only affects " +
                  "default namespace assignments.",
        ),
        "release_name": attr.string(
            doc = "Helm release name (the first positional arg to " +
                  "`helm template`). Defaults to the target name.",
        ),
        "kube_version": attr.string(
            doc = "Sets `--kube-version`. Some charts gate features on " +
                  "`semverCompare \">=1.30\" .Capabilities.KubeVersion`; " +
                  "pin this to match your target cluster.",
        ),
        "api_versions": attr.string_list(
            doc = "Sets `--api-versions <gv>` once per entry. Use when a " +
                  "chart consults `.Capabilities.APIVersions.Has`.",
        ),
        "include_crds": attr.bool(
            default = False,
            doc = "Sets `--include-crds`. Off by default (helm's default).",
        ),
        "helm_template_args": attr.string_list(
            doc = "Extra args passed verbatim to `helm template`, after " +
                  "all attribute-derived flags. Escape hatch for flags " +
                  "this rule doesn't surface explicitly.",
        ),
    },
    toolchains = ["//toolchain:helm"],
)
