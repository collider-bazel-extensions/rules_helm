"""Analysis-time tests. Verify rules instantiate cleanly and expose
DefaultInfo without invoking helm at analysis time."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_helm//:defs.bzl", "helm_lint", "helm_package", "helm_template")

def _has_default_info_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo] != None,
        "expected target to expose DefaultInfo",
    )
    return analysistest.end(env)

_has_default_info_test = analysistest.make(_has_default_info_impl)

def _has_executable_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo].files_to_run.executable != None,
        "expected target to expose an executable",
    )
    return analysistest.end(env)

_has_executable_test = analysistest.make(_has_executable_impl)

def helm_template_test_suite(name):
    helm_template(
        name = name + "_subject",
        chart = ["//tests/example_chart:files"],
        tags = ["manual"],
    )
    _has_default_info_test(
        name = name + "_default_info",
        target_under_test = ":" + name + "_subject",
    )
    native.test_suite(name = name, tests = [":" + name + "_default_info"])

def helm_lint_test_suite(name):
    helm_lint(
        name = name + "_subject",
        chart = ["//tests/example_chart:files"],
        tags = ["manual"],
    )
    _has_executable_test(
        name = name + "_executable",
        target_under_test = ":" + name + "_subject",
    )
    native.test_suite(name = name, tests = [":" + name + "_executable"])

def helm_package_test_suite(name):
    helm_package(
        name = name + "_subject",
        chart = ["//tests/example_chart:files"],
        tags = ["manual"],
    )
    _has_default_info_test(
        name = name + "_default_info",
        target_under_test = ":" + name + "_subject",
    )
    native.test_suite(name = name, tests = [":" + name + "_default_info"])
