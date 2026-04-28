# rules_helm

Hermetic [Helm](https://helm.sh/) CLI for Bazel. Three rules:

- **`helm_template`** — action rule that renders a chart directory to a
  single YAML file at build time. The hermetic Bazel-native equivalent
  of `helm template <release> <chart-dir> > out.yaml`.
- **`helm_package`** — action rule that produces a **deterministic**
  `.tgz` chart archive. Wraps `helm package` and re-packs with
  normalized metadata (mtime=0, sorted entries, gzip without timestamp)
  so the bytes are reproducible across builds.
- **`helm_lint`** — test rule that runs `helm lint <chart>` and fails
  the test on non-zero exit.

Pure CLI — no cluster, no network at test time. The helm binary itself
is sha256-pinned and downloaded by the bzlmod extension.

**Supported platforms (v0.1):** Linux x86\_64, macOS x86\_64, macOS arm64.
Linux validated in CI; macOS pending. See [Contributing](#contributing).

**Pinned versions (selectable):** Helm 3.20.2 (default) or Helm 4.1.4.
Pick via `helm.version(version = "...")` in your `MODULE.bazel`.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Rules](#rules)
  - [helm\_template](#helm_template)
  - [helm\_package](#helm_package)
  - [helm\_lint](#helm_lint)
- [Providers](#providers)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_helm", version = "0.2.0")

helm = use_extension("@rules_helm//:extensions.bzl", "helm")
helm.version(version = "3.20.2")  # or "4.1.4"

use_repo(helm,
    "helm_linux_amd64",
    "helm_darwin_amd64",
    "helm_darwin_arm64",
)

register_toolchains(
    "@helm_linux_amd64//:toolchain",
    "@helm_darwin_amd64//:toolchain",
    "@helm_darwin_arm64//:toolchain",
)
```

Each per-platform repo emits its own `:toolchain` carrying the version
that was actually fetched, so `HelmInfo.version` reflects what
`helm.version()` chose rather than a hardcoded value.

`rules_helm` is **Bzlmod-only** in v0.1. Until it lands in BCR, consume
via `archive_override` or a git pin pointing at a tag.

---

## Quickstart

Layout your helm chart the way helm itself recommends — a directory
with `Chart.yaml` at the root:

```
my/chart/
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
  BUILD.bazel
```

```python
load("@rules_helm//:defs.bzl", "helm_lint", "helm_template")

filegroup(
    name = "files",
    srcs = glob(["**"]),
)

helm_template(
    name = "rendered",
    chart = [":files"],
    set_strings = {"image.tag": "v1.2.3"},
    namespace = "production",
    release_name = "my-app",
)

helm_lint(
    name = "lint",
    chart = [":files"],
    strict = True,
)
```

`bazel build //my/chart:rendered` produces `my/chart/rendered.yaml`.
`bazel test //my/chart:lint` runs `helm lint --strict`.

---

## Rules

### `helm_template`

Action rule wrapping `helm template <release> <chart-dir> [flags...]`,
captured to a single YAML output file.

```python
helm_template(
    name = "rendered",
    chart = [":files"],                    # filegroup of all chart files
    values = ["overrides.yaml"],           # optional, applied via -f in order
    set = {"replicas": "3"},               # optional, --set
    set_strings = {"image.tag": "1.2.3"},  # optional, --set-string
    namespace = "prod",                    # optional, --namespace
    release_name = "my-app",               # optional, defaults to target name
    kube_version = "1.32.0",               # optional, --kube-version
    api_versions = ["apps/v1"],            # optional, --api-versions
    include_crds = True,                   # optional, --include-crds
    helm_template_args = ["--debug"],      # escape hatch
)
```

The output is a single file named `<name>.yaml`. The rule scans `chart`
for `Chart.yaml` to determine the chart root.

### `helm_package`

Action rule wrapping `helm package <chart-dir>`, then re-packing the
resulting tarball with normalized metadata so the output is
reproducible.

```python
helm_package(
    name = "chart_tgz",
    chart = [":files"],            # filegroup of all chart files
    chart_version = "1.2.3",       # optional, --version (overrides Chart.yaml)
    app_version = "1.0",           # optional, --app-version
    helm_package_args = [],        # escape hatch
)
```

The output is a single file named `<name>.tgz`. Every entry has
`mtime=0`, sorted alphabetically; the gzip header has no timestamp or
filename. Two builds against the same inputs produce byte-identical
`.tgz` files.

If you need the canonical `<chartname>-<version>.tgz` filename, rename
downstream via a `genrule` or `pkg_tar`.

### `helm_lint`

Bazel test rule wrapping `helm lint <chart-dir>`. Fails the test on
non-zero exit.

```python
helm_lint(
    name = "lint",
    chart = [":files"],
    values = ["overrides.yaml"],   # optional, lets lint evaluate templates
    strict = True,                 # treats warnings as errors
)
```

Run with `bazel test //my/chart:lint`.

---

## Providers

### `HelmInfo`

| Field | Type | Description |
|---|---|---|
| `version` | `string` | Helm version, e.g. `"3.20.2"` |
| `helm_bin` | `File` | The platform-resolved, sha256-verified helm executable |

Custom rules that want the binary can resolve it via the toolchain:

```python
def _impl(ctx):
    info = ctx.toolchains["@rules_helm//toolchain:helm"].helm
    # info.helm_bin is a File; info.version is a string

my_rule = rule(
    implementation = _impl,
    toolchains = ["@rules_helm//toolchain:helm"],
)
```

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| Helm binary | Fully hermetic. URL + sha256 pinned per platform in `private/versions.bzl`. | Update via `bash tools/update_versions.sh <version> --update`. |
| Chart inputs | Whatever you pass via `chart` / `values`. | Must be Bazel-tracked files. |
| Networked dependencies | **Subchart `dependencies:` are NOT auto-fetched.** Run `helm dependency update` against your chart at maintainer time and commit the resulting `charts/*.tgz` into your tree (then `glob(["**"])` picks them up). v0.1 does not run `helm dep update` at build time — hermeticity. | Future: a `helm_dependency_update` write-back rule. |

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping the pinned Helm version: `bash tools/update_versions.sh <new-version> --update`.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted: macOS validation

The toolchain selection is symmetric across platforms, but no one has
run the example tests on Darwin yet. A pasted log from a green
`bazel test //tests:all` on macOS would unblock the macOS support claim.
