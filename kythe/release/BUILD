load("//tools:build_rules/docker.bzl", "docker_build")

# See setup_release.sh for instructions on creating a release

docker_build(
    name = "docker",
    data = [
        "kythe.sh",
        "maven_extractor.sh",
        "//kythe/cxx/indexer/cxx:indexer",
        "//kythe/go/indexer/cmd/go_indexer",
        "//kythe/go/platform/tools/dedup_stream",
        "//kythe/go/storage/tools:directory_indexer",
        "//kythe/go/storage/tools:write_entries",
        "//kythe/java/com/google/devtools/kythe/analyzers/java:indexer_deploy.jar",
        "//kythe/java/com/google/devtools/kythe/analyzers/jvm:class_file_indexer_deploy.jar",
        "//kythe/java/com/google/devtools/kythe/extractors/java/standalone:javac_extractor_deploy.jar",
        "//third_party/javac:javac_jar",
    ],
    image_name = "google/kythe",
    tags = ["manual"],
    use_cache = True,
    deps = ["//kythe/release/base"],
)

release_version = "v0.0.29"

genrule(
    name = "release",
    srcs = [
        ":bazel_java_extractor",
        ":bazel_cxx_extractor",
        ":bazel_go_extractor",
        ":javac_extractor",
        ":javac_wrapper",
        ":cxx_extractor",
        ":go_extractor",
        ":java_indexer",
        ":jvm_indexer",
        ":cxx_indexer",
        ":go_indexer",
        ":tools",
        ":misc",
        "//kythe/proto:public",
        "//kythe/web/ui",
        "//third_party:licenses",
    ],
    outs = [
        "kythe-" + release_version + ".tar.gz",
        "kythe-" + release_version + ".tar.gz.sha256",
    ],
    cmd = " ".join([
        "export GENDIR=$(GENDIR);",
        "export BINDIR=$(BINDIR);",
        "$(location package_release.sh)",
        "$(location //kythe/go/platform/tools/shasum_tool)",
        "$(location kythe-" + release_version + ".tar.gz)",
        "$(locations misc)",
        "--cp $(location java_indexer) indexers/java_indexer.jar",
        "--cp $(location jvm_indexer) indexers/jvm_indexer.jar",
        "--cp $(location cxx_indexer) indexers/cxx_indexer",
        "--cp $(location go_indexer) indexers/go_indexer",
        "--cp $(location javac_extractor) extractors/javac_extractor.jar",
        "--cp $(location bazel_cxx_extractor) extractors/bazel_cxx_extractor",
        "--cp $(location bazel_java_extractor) extractors/bazel_java_extractor.jar",
        "--cp $(location bazel_go_extractor) extractors/bazel_go_extractor",
        "--cp $(location javac_wrapper) extractors/javac-wrapper.sh",
        "--cp $(location cxx_extractor) extractors/cxx_extractor",
        "--cp $(location go_extractor) extractors/go_extractor",
        "--path tools/ $(locations tools)",
        "--path proto/ $(locations //kythe/proto:public)",
        "--relpaths kythe/web/ui/resources/public",
        "--path web/ui $(locations //kythe/web/ui)",
        "--relpaths 'third_party' --path 'third_party' $(locations //third_party:licenses)",
    ]),
    heuristic_label_expansion = False,
    tags = ["manual"],
    tools = [
        "package_release.sh",
        "//kythe/go/platform/tools/shasum_tool",
    ],
)

filegroup(
    name = "misc",
    srcs = [
        ":README.md",
        "//:LICENSE",
        "//:RELEASES.md",
    ],
)

sh_test(
    name = "release_test",
    timeout = "short",
    srcs = ["release_test.sh"],
    args = [
        # Since go binaries are not located at their bazel target path (//go/binary
        # might be in bazel-out/go/binary/host/text/binary), pass the actual
        # location of the binary directly to the shell script.
        "$(location //kythe/go/platform/tools/shasum_tool)",
    ],
    data = [
        ":release",
        "//kythe/go/platform/tools/shasum_tool",
        "//kythe/java/com/google/devtools/kythe/util:test_srcs",
        "//kythe/testdata:entries",
        "//kythe/testdata:test.kindex",
        "//third_party/guava",
        "//third_party/javac:javac_jar",
        "@com_github_stedolan_jq//:jq",
    ],
    tags = [
        "local",
        "manual",
    ],
)

filegroup(
    name = "javac_extractor",
    srcs = ["//kythe/java/com/google/devtools/kythe/extractors/java/standalone:javac_extractor_deploy.jar"],
)

filegroup(
    name = "javac_wrapper",
    srcs = ["//kythe/java/com/google/devtools/kythe/extractors/java/standalone:javac-wrapper.sh"],
)

filegroup(
    name = "bazel_java_extractor",
    srcs = ["//kythe/java/com/google/devtools/kythe/extractors/java/bazel:java_extractor_deploy.jar"],
)

filegroup(
    name = "cxx_extractor",
    srcs = ["//kythe/cxx/extractor:cxx_extractor"],
)

filegroup(
    name = "bazel_cxx_extractor",
    srcs = ["//kythe/cxx/extractor:cxx_extractor_bazel"],
)

filegroup(
    name = "go_extractor",
    srcs = ["//kythe/go/extractors/cmd/gotool"],
)

filegroup(
    name = "bazel_go_extractor",
    srcs = ["//kythe/go/extractors/cmd/bazel:bazel_go_extractor"],
)

filegroup(
    name = "java_indexer",
    srcs = ["//kythe/java/com/google/devtools/kythe/analyzers/java:indexer_deploy.jar"],
)

filegroup(
    name = "jvm_indexer",
    srcs = ["//kythe/java/com/google/devtools/kythe/analyzers/jvm:class_file_indexer_deploy.jar"],
)

filegroup(
    name = "cxx_indexer",
    srcs = ["//kythe/cxx/indexer/cxx:indexer"],
)

filegroup(
    name = "go_indexer",
    srcs = ["//kythe/go/indexer/cmd/go_indexer"],
)

filegroup(
    name = "tools",
    srcs = [
        "//kythe/cxx/verifier",
        "//kythe/go/platform/tools/dedup_stream",
        "//kythe/go/platform/tools/entrystream",
        "//kythe/go/platform/tools/indexpack",
        "//kythe/go/platform/tools/viewindex",
        "//kythe/go/serving/tools:http_server",
        "//kythe/go/serving/tools:kythe",
        "//kythe/go/serving/tools:write_tables",
        "//kythe/go/storage/tools:directory_indexer",
        "//kythe/go/storage/tools:read_entries",
        "//kythe/go/storage/tools:triples",
        "//kythe/go/storage/tools:write_entries",
    ],
)
