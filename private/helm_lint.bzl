"""helm_lint — Bazel test rule that runs `helm lint <chart>` and fails
the test on non-zero exit.

Same chart input shape as `helm_template`: a `label_list` containing the
chart's files (including Chart.yaml). Lint uses the same chart-root
detection logic.
"""

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:helm"]
    helm = tc.helm.helm_bin

    chart_yaml = None
    for f in ctx.files.chart:
        if f.basename == "Chart.yaml":
            chart_yaml = f
            break
    if chart_yaml == None:
        fail("helm_lint {}: chart attr must include a Chart.yaml file".format(ctx.label))

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{HELM_BIN}":   helm.short_path,
            "{CHART_ROOT}": chart_yaml.dirname,
            "{STRICT}":     "--strict" if ctx.attr.strict else "",
            "{EXTRA}":      " ".join(["'" + a + "'" for a in ctx.attr.helm_lint_args]),
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [helm] + ctx.files.chart + ctx.files.values)
    return [DefaultInfo(executable = out, runfiles = runfiles)]

_helm_lint_rule_test = rule(
    implementation = _impl,
    test = True,
    attrs = {
        "chart": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Chart files, same shape as `helm_template.chart`.",
        ),
        "values": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Optional values files passed via `-f`. Lint can " +
                  "evaluate templates against values to catch render-time " +
                  "errors that `helm lint` alone misses.",
        ),
        "strict": attr.bool(
            default = False,
            doc = "Pass `--strict`, which treats lint warnings as errors.",
        ),
        "helm_lint_args": attr.string_list(
            doc = "Extra args passed verbatim to `helm lint`.",
        ),
        "_tmpl": attr.label(
            default = "//private:helm_lint.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:helm"],
)

def helm_lint(name, chart, **kwargs):
    """Wraps the underlying test rule so the public name doesn't need a
    `_test` suffix. Bazel requires test-rule *class* names to end with
    `_test`, but consumers prefer plain `helm_lint(...)`."""
    _helm_lint_rule_test(name = name, chart = chart, **kwargs)
