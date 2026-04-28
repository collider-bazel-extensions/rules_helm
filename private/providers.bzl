"""Providers exported by rules_helm."""

HelmInfo = provider(
    doc = "The resolved Helm install: pinned version + path to the " +
          "downloaded, sha256-verified `helm` executable.",
    fields = {
        "version":  "Helm version string, e.g. '3.20.2'.",
        "helm_bin": "File: the platform-specific helm executable.",
    },
)
