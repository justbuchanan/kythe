# Copyright 2019 The Kythe Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load(
    ":verifier_test.bzl",
    "KytheVerifierSources",
    "extract",
    "index_compilation",
    "verifier_test",
)
load(":xlang_proto_verifier_test.bzl", "xlang_proto_verifier_test")

KytheJavaParamsInfo = provider(
    doc = "Java source jar unpacked into parameters file.",
    fields = {
        "srcjar": "Original source jar generating files in params file.",
        "params": "File with list of Java parameters.",
        "dir": "Directory of files referenced in params file.",
    },
)

def _invoke(rulefn, name, **kwargs):
    """Invoke rulefn with name and kwargs, returning the label of the rule."""
    rulefn(name = name, **kwargs)
    return "//{}:{}".format(native.package_name(), name)

def _java_extract_kzip_impl(ctx):
    deps = [dep[JavaInfo] for dep in ctx.attr.deps]

    srcs = []
    srcjars = []
    params_files = []
    dirs = []
    for src in ctx.attr.srcs:
        if KytheJavaParamsInfo in src:
            srcjars += [src[KytheJavaParamsInfo].srcjar]
            params_files += [src[KytheJavaParamsInfo].params]
            dirs += [src[KytheJavaParamsInfo].dir]
        else:
            srcs += [src.files]
    srcs = depset(transitive = srcs).to_list()

    # Actually compile the sources to be used as a dependency for other tests
    jar = ctx.actions.declare_file(ctx.outputs.kzip.basename + ".jar", sibling = ctx.outputs.kzip)
    java_info = java_common.compile(
        ctx,
        javac_opts = ctx.attr.opts,
        java_toolchain = ctx.attr._java_toolchain,
        host_javabase = ctx.attr._host_javabase,
        source_jars = srcjars,
        source_files = srcs,
        output = jar,
        deps = deps,
    )

    jars = depset(transitive = [dep.compile_jars for dep in deps]).to_list()
    args = ctx.attr.opts + [
        "-encoding",
        "utf-8",
        "-cp",
        ":".join([j.path for j in jars]),
    ]
    for params in params_files:
        args += ["@" + params.path]
    for src in srcs:
        args += [src.short_path]
    extract(
        srcs = srcs,
        ctx = ctx,
        extractor = ctx.executable.extractor,
        kzip = ctx.outputs.kzip,
        mnemonic = "JavaExtractKZip",
        opts = args,
        vnames_config = ctx.file.vnames_config,
        deps = jars + ctx.files.data + params_files + dirs,
    )
    return [
        java_info,
        KytheVerifierSources(files = depset(srcs)),
    ]

java_extract_kzip = rule(
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_empty = False,
            allow_files = True,
        ),
        "data": attr.label_list(
            allow_files = True,
        ),
        "extractor": attr.label(
            default = Label("@io_kythe//kythe/java/com/google/devtools/kythe/extractors/java/standalone:javac_extractor"),
            executable = True,
            cfg = "host",
        ),
        "opts": attr.string_list(),
        "vnames_config": attr.label(
            default = Label("//external:vnames_config"),
            allow_single_file = True,
        ),
        "deps": attr.label_list(
            providers = [JavaInfo],
        ),
        "_host_javabase": attr.label(
            cfg = "host",
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
        ),
        "_java_toolchain": attr.label(
            default = Label("@bazel_tools//tools/jdk:toolchain"),
        ),
    },
    fragments = ["java"],
    host_fragments = ["java"],
    outputs = {"kzip": "%{name}.kzip"},
    implementation = _java_extract_kzip_impl,
)

_default_java_extractor_opts = [
    "-source",
    "9",
    "-target",
    "9",
]

def java_verifier_test(
        name,
        srcs,
        meta = [],
        deps = [],
        size = "small",
        tags = [],
        extractor = None,
        extractor_opts = _default_java_extractor_opts,
        indexer_opts = ["--verbose"],
        verifier_opts = ["--ignore_dups"],
        load_plugin = None,
        extra_goals = [],
        vnames_config = None,
        visibility = None):
    """Extract, analyze, and verify a Java compilation.

    Args:
      srcs: The compilation's source file inputs; each file's verifier goals will be checked
      deps: Optional list of java_verifier_test targets to be used as Java compilation dependencies
      meta: Optional list of Kythe metadata files
      extractor: Executable extractor tool to invoke (defaults to javac_extractor)
      extractor_opts: List of options passed to the extractor tool
      indexer_opts: List of options passed to the indexer tool
      verifier_opts: List of options passed to the verifier tool
      load_plugin: Optional Java analyzer plugin to load
      extra_goals: List of text files containing verifier goals additional to those in srcs
      vnames_config: Optional path to a VName configuration file
    """
    kzip = _invoke(
        java_extract_kzip,
        name = name + "_kzip",
        testonly = True,
        srcs = srcs,
        data = meta,
        extractor = extractor,
        opts = extractor_opts,
        tags = tags,
        visibility = visibility,
        vnames_config = vnames_config,
        # This is a hack to depend on the .jar producer.
        deps = [d + "_kzip" for d in deps],
    )
    indexer = "//kythe/java/com/google/devtools/kythe/analyzers/java:indexer"
    tools = []
    if load_plugin:
        # If loaded plugins have deps, those must be included in the loaded jar
        native.java_binary(
            name = name + "_load_plugin",
            main_class = "not.Used",
            runtime_deps = [load_plugin],
        )
        load_plugin_deploy_jar = ":{}_load_plugin_deploy.jar".format(name)
        indexer_opts = indexer_opts + [
            "--load_plugin",
            "$(location {})".format(load_plugin_deploy_jar),
        ]
        tools += [load_plugin_deploy_jar]

    entries = _invoke(
        index_compilation,
        name = name + "_entries",
        testonly = True,
        indexer = indexer,
        opts = indexer_opts,
        tags = tags,
        tools = tools,
        visibility = visibility,
        deps = [kzip],
    )
    return _invoke(
        verifier_test,
        name = name,
        size = size,
        srcs = [entries] + extra_goals,
        opts = verifier_opts,
        tags = tags,
        visibility = visibility,
        deps = [entries],
    )

def _generate_java_proto_impl(ctx):
    # Generate the Java protocol buffer sources into a directory.
    # Note: out contains .meta files with annotations for cross-language xrefs.
    out = ctx.actions.declare_directory(ctx.label.name)
    protoc = ctx.executable._protoc
    ctx.actions.run_shell(
        outputs = [out],
        inputs = ctx.files.srcs,
        tools = [protoc],
        command = "\n".join([
            "#/bin/bash",
            "set -e",
            # Creating the declared directory in this action is necessary for
            # remote execution environments.  This differs from local execution
            # where Bazel will create the directory before this action is
            # executed.
            "mkdir -p " + out.path,
            " ".join([
                protoc.path,
                "--java_out=annotate_code:" + out.path,
            ] + [src.path for src in ctx.files.srcs]),
        ]),
    )

    # List the Java sources in a files for the javac_extractor to take as a @params file.
    files = ctx.actions.declare_file(ctx.label.name + ".files")
    ctx.actions.run_shell(
        outputs = [files],
        inputs = [out],
        command = "find " + out.path + " -name '*.java' >" + files.path,
    )

    # Produce a source jar file for the native Java compilation in the java_extract_kzip rule.
    # Note: we can't use java_common.pack_sources because our input is a directory.
    singlejar = ctx.attr._java_toolchain.java_toolchain.single_jar
    srcjar = ctx.actions.declare_file(ctx.label.name + ".srcjar")
    ctx.actions.run(
        outputs = [srcjar],
        inputs = [out, files],
        executable = singlejar,
        arguments = ["--output", srcjar.path, "--resources", "@" + files.path],
    )

    return [
        DefaultInfo(files = depset([files, out, srcjar])),
        KytheJavaParamsInfo(dir = out, params = files, srcjar = srcjar),
    ]

_generate_java_proto = rule(
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            providers = [JavaInfo],
        ),
        "_protoc": attr.label(
            default = Label("@com_google_protobuf//:protoc"),
            executable = True,
            cfg = "host",
        ),
        "_java_toolchain": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_toolchain"),
        ),
    },
    implementation = _generate_java_proto_impl,
)

def java_proto_verifier_test(
        name,
        srcs,
        size = "small",
        proto_srcs = [],
        tags = [],
        java_extractor_opts = _default_java_extractor_opts,
        verifier_opts = ["--ignore_dups"],
        vnames_config = None,
        visibility = None):
    xlang_proto_verifier_test(
        name = name,
        srcs = srcs,
        size = size,
        proto_srcs = proto_srcs,
        genlang_extractor_opts = java_extractor_opts,
        genlang_extractor_deps = [
            "@com_google_protobuf//:protobuf_java",
            "@javax_annotation_jsr250_api//jar",
        ],
        genlang_indexer_opts=['--verbose'],
        visibility = visibility,
        vnames_config = vnames_config,
        verifier_opts = verifier_opts,
        build_annotated_generated_code_rule = _generate_java_proto,
        genlang_extract_rule = java_extract_kzip,
        genlang_indexer = "//kythe/java/com/google/devtools/kythe/analyzers/java:indexer",
    )
