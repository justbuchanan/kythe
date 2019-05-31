load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def maybe(repo_rule, name, **kwargs):
    """Defines a repository if it does not already exist.
    """
    if name not in native.existing_rules():
        repo_rule(name = name, **kwargs)

def kythe_deps():
    """Defines external repositories required by kythe release.
    """
    maybe(
        http_archive,
        name = "com_google_protobuf",
        sha256 = "ef62ee52bedc3a0ec0aeb7911279243119d53eac7f8bbbec833761c07e802bcb",
        strip_prefix = "protobuf-8e5ea65953f3c47e01bca360ecf3abdf2c8b1c33",
        urls = ["https://github.com/protocolbuffers/protobuf/archive/8e5ea65953f3c47e01bca360ecf3abdf2c8b1c33.zip"],
    )

    maybe(
        http_archive,
        name = "bazel_skylib",
        sha256 = "ca4e3b8e4da9266c3a9101c8f4704fe2e20eb5625b2a6a7d2d7d45e3dd4efffd",
        strip_prefix = "bazel-skylib-0.5.0",
        urls = ["https://github.com/bazelbuild/bazel-skylib/archive/0.5.0.zip"],
    )
