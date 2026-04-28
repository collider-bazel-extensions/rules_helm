# rules_helm — design decisions

Hermetic [Helm](https://helm.sh/) CLI for Bazel: `helm_template` (action
rule producing rendered YAML) and `helm_lint` (test rule). Pure CLI — no
cluster, no network at test time.

Same family as `rules_opa`: a Bazel-native test/build wrapper around a
hermetic CLI. Distinct from the in-cluster operator rules
(`rules_certmanager`, `rules_cilium`, `rules_argocd`, …).

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** | rules_opa precedent |
| 2 | Module extension shape | One tag class: `version` (download). | rules_opa |
| 3 | Toolchain type | `HELM_TOOLCHAIN_TYPE = Label("//toolchain:helm")`. `ToolchainInfo(helm = …)` carries the binary path. Per-platform `toolchain` declarations select based on the resolved exec platform. | rules_opa |
| 4 | Binary provisioning | Per-platform `helm_<plat>` repos download + extract the upstream tarball at the sha256 pinned in `private/versions.bzl`. Helm ships in a `.tar.gz` (unlike OPA which is a bare binary), so we use `download_and_extract` and `strip_prefix` to lift the binary to a stable top-level path. | Helm-specific divergence from rules_opa |
| 5 | Pinned helm major | **v3.x** (`v3.20.2`). Helm v4 is current too but introduces breaking changes to template engine + plugin structure; the existing maintainer scripts in `rules_capsule` / `rules_cilium` were written against v3 syntax and bumping is out of scope here. v4 can land as another version entry later. | Compatibility |
| 6 | Public surface | `helm_template` (action rule), `helm_lint` (test rule), `HelmInfo` provider. | Helm-specific |
| 7 | Chart input shape | `chart = label_list(allow_files = True)` — typically `glob(['my_chart/**'])`. The rule scans for `Chart.yaml` to determine the chart root. Single-file tarball input was rejected for v0.1 because chart authors usually maintain a directory tree, not a `.tgz`. | Helm-specific |
| 8 | `helm_template` action shape | `ctx.actions.run_shell` with stdout redirected into the declared `<name>.yaml` output. All args single-quoted to defend against paths or attr strings with shell metacharacters. | Helm-specific |
| 9 | Test-rule naming | `helm_lint` is a test rule; Bazel requires test-rule *class* names to end with `_test`. The rule class is `_helm_lint_rule_test`; a public macro `helm_lint(name, chart, **kwargs)` keeps the consumer-facing name clean. Same workaround as `rules_opa`'s `opa_fmt_check`. | Bazel constraint |
| 10 | Hermeticity | The helm binary is the only external input; pinned by sha256 per platform. No host helm, no network at test time. Tests run in the Bazel sandbox. | Sibling-family policy |
| 11 | Platform matrix v1 | linux_amd64, darwin_amd64, darwin_arm64. Linux validated in CI; macOS unvalidated. | Sibling family |
| 12 | MODULE deps | `bazel_skylib`, `platforms`. **No `rules_python`** (no python in the runtime path). `rules_shell` is dev-only for the in-tree YAML-assertion test. | Smallest viable |
| 13 | Naming | snake_case rules, `MixedCaseInfo` providers (`HelmInfo`), `UPPER_SNAKE` constants. | All siblings |
| 14 | Update workflow | `tools/update_versions.sh <version>` curls per-platform `.sha256sum` companions and rewrites `private/versions.bzl`. | rules_opa pattern |

## Notes

- `helm_template` exposes the surface the maintainer scripts in `rules_capsule` / `rules_cilium` use today: positional release name + chart, plus `--namespace`, `-f values`, `--set/--set-string`, `--kube-version`, `--api-versions`, `--include-crds`. An `helm_template_args` escape hatch handles flags this rule doesn't surface explicitly.
- `helm_lint` runs against the same chart inputs as `helm_template`; the chart-root detection logic is shared (find Chart.yaml among the inputs). Adding values lets lint evaluate templates against them, which catches render-time errors `helm lint` alone misses.
- Future refactor: the maintainer scripts in `rules_capsule` / `rules_cilium` could be replaced by `helm_template` rules at maintainer build time, with the rendered YAML committed back via a `bazel run` write-back target. Out of scope for v0.1 of either project; mention the path here so it's not forgotten.

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| Module extension (`version` only) | planned |
| Pinned Helm 3.20.2 per-platform sha256 | planned |
| `helm_template` action rule | planned |
| `helm_lint` test rule | planned |
| Per-platform toolchain declarations | planned |
| Analysis tests | planned |
| End-to-end exercise via `tests/example_chart/` (real helm template + lint, plus YAML-content assertion) | planned |
| End-to-end `bazel test` runtime | planned (validated under CI; macOS pending) |

## v0.2.0 (2026-04-28)

- **`helm_package`** shipped. Wraps `helm package` then re-packs the resulting `.tgz` with `tar --mtime='@0' --sort=name --owner=0 --group=0 --numeric-owner` and `gzip -n -9`. Two builds against the same chart inputs produce byte-identical archives. End-to-end test asserts every entry in the produced tarball has 1970-01-01 mtime.
- **Helm 4.1.4** added alongside 3.20.2 in `HELM_VERSIONS`. Default remains 3.20.2 (the existing maintainer scripts in `rules_capsule` / `rules_cilium` are written against v3 syntax). Pick v4 via `helm.version(version = "4.1.4")`.
- **Toolchain emission moved to per-platform repo.** Previously `//toolchain:BUILD.bazel` declared toolchain instances with a hardcoded version; now each `helm_<plat>` repo (created by the module extension) emits its own `:toolchain_impl` + `:toolchain` at the version that was actually fetched. Consumers register `@helm_<plat>//:toolchain` instead of `@rules_helm//toolchain:all`. Fixes a v0.1 wart: `HelmInfo.version` now reflects `helm.version()` instead of a hardcoded "3.20.2".

## Deferred (not v0.2.0)

- **`helm_push`** — push to an OCI registry. Needs registry creds; out of scope for a hermetic CLI rule set.
- **`helm_install` / `helm_upgrade`** — runtime path against a live cluster. The in-cluster operator rule sets (`rules_certmanager`, `rules_cilium`, etc.) cover this need via their `*_install` rules; rules_helm is the build-time CLI rule set.
- **Helm v4 as default** — wait until the existing maintainer scripts in `rules_capsule` / `rules_cilium` are validated against v4. v4 is shipped as a parallel version entry now, not the default.
- **`system` extension mode** — `helm.system()` to honor host-installed `helm`. Add when a consumer asks.
- **Multi-version `use_repo` shape** — currently a consumer can call `helm.version()` exactly once. Supporting multiple versions side-by-side (`helm_3_20_2_<plat>` + `helm_4_1_4_<plat>`) is a deeper rework; defer until a real consumer wants it.
