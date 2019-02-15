#
# Copyright 2016 The Kythe Authors. All rights reserved.
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
#

KytheVerifierSources = provider(
    doc = "Input files which the verifier should inspect for assertions.",
    fields = {
        "files": "Depset of files which should be considered.",
    },
)

KytheEntries = provider(
    doc = "Kythe indexer entry facts.",
    fields = {
        "compressed": "Depset of combined, compressed index entries.",
        "files": "Depset of files which combine to make an index.",
    },
)

def _atomize_entries_impl(ctx):
    zcat = ctx.executable._zcat
    entrystream = ctx.executable._entrystream
    postprocessor = ctx.executable._postprocessor
    atomizer = ctx.executable._atomizer

    inputs = depset(ctx.files.srcs)
    for dep in ctx.attr.deps:
        inputs += dep.kythe_entries

    sorted_entries = ctx.actions.declare_file("_sorted_entries", sibling = ctx.outputs.entries)
    ctx.actions.run_shell(
        outputs = [sorted_entries],
        inputs = [zcat, entrystream] + inputs.to_list(),
        mnemonic = "SortEntries",
        command = '("$1" "${@:4}" | "$2" --sort) > "$3" || rm -f "$3"',
        arguments = (
            [zcat.path, entrystream.path, sorted_entries.path] + [s.path for s in inputs.to_list()]
        ),
    )
    leveldb = ctx.actions.declare_file("_serving_tables", sibling = ctx.outputs.entries)
    ctx.actions.run(
        outputs = [leveldb],
        inputs = [sorted_entries, postprocessor],
        executable = postprocessor,
        mnemonic = "PostProcessEntries",
        arguments = ["--entries", sorted_entries.path, "--out", leveldb.path],
    )
    ctx.actions.run_shell(
        outputs = [ctx.outputs.entries],
        inputs = [atomizer, leveldb],
        mnemonic = "AtomizeEntries",
        command = '("${@:1:${#@}-1}" || rm -f "${@:${#@}}") | gzip -c > "${@:${#@}}"',
        arguments = ([atomizer.path, "--api", leveldb.path] + ctx.attr.file_tickets + [ctx.outputs.entries.path]),
        execution_requirements = {
            # TODO(shahms): Remove this when we can use a non-LevelDB store.
            "local": "true",  # LevelDB is bad and should feel bad.
        },
    )
    return struct()

atomize_entries = rule(
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [
                ".entries",
                ".entries.gz",
            ],
        ),
        "file_tickets": attr.string_list(
            mandatory = True,
            allow_empty = False,
        ),
        "deps": attr.label_list(
            providers = ["kythe_entries"],
        ),
        "_atomizer": attr.label(
            default = Label("//kythe/go/test/tools:xrefs_atomizer"),
            executable = True,
            cfg = "host",
        ),
        "_entrystream": attr.label(
            default = Label("//kythe/go/platform/tools/entrystream"),
            executable = True,
            cfg = "host",
        ),
        "_postprocessor": attr.label(
            default = Label("//kythe/go/serving/tools/write_tables"),
            executable = True,
            cfg = "host",
        ),
        "_zcat": attr.label(
            default = Label("//tools:zcatext"),
            executable = True,
            cfg = "host",
        ),
    },
    outputs = {
        "entries": "%{name}.entries.gz",
    },
    implementation = _atomize_entries_impl,
)

def extract(
        ctx,
        kzip,
        extractor,
        srcs,
        opts,
        deps = [],
        vnames_config = None,
        mnemonic = "ExtractCompilation"):
    """Run the extractor tool under an environment to produce the given kzip
    output file.  The extractor is passed each string from opts after expanding
    any build artifact locations and then each File's path from the srcs
    collection.

    Args:
      kzip: Declared .kzip output File
      extractor: Executable extractor tool to invoke
      srcs: Files passed to extractor tool; the compilation's source file inputs
      opts: List of options passed to the extractor tool before source files
      deps: Dependencies for the extractor's action (not passed to extractor on command-line)
      vnames_config: Optional path to a VName configuration file
      mnemonic: Mnemonic of the extractor's action
    """
    env = {
        "KYTHE_OUTPUT_FILE": kzip.path,
        "KYTHE_ROOT_DIRECTORY": ".",
    }
    inputs = srcs + [d.files if hasattr(d, 'files') else d for d in deps]

    for d in deps:
        if hasattr(d, 'hdrs'):
            print("HEADERS" + d.hdrs)
        else:
            print("no headeres")

        if not type(d) == :
            if CcInfo in d:
                print("CC INFO")

    if vnames_config:
        env["KYTHE_VNAMES"] = vnames_config.path
        inputs += [vnames_config]
    print("extract() inputs: {}".format(inputs))
    # print("extract() inputs[2].path: {}".format(inputs[2].path))
    # print("extract() inputs[2].root: {}".format(inputs[2].root.path))
    for d in deps:
        print("DEP: " + str(d))
    ctx.actions.run_shell(
        inputs = inputs,
        tools = [extractor],
        outputs = [kzip],
        mnemonic = mnemonic,
        # executable = extractor,
        command = (
            "tree && ls kythe/cxx/indexer/cxx/testdata/proto && " + extractor.path + " -I" + inputs[1].root.path + " " + " ".join([ctx.expand_location(o) for o in opts] +
            [src.path for src in srcs]) + " && echo 'PATH: " + " ".join([d.path for d in deps]) + "'"
        ),
        env = env,
    )
    return kzip

def _index_compilation_impl(ctx):
    sources = []
    intermediates = []
    for dep in ctx.attr.deps:
        if KytheVerifierSources in dep:
            sources += [dep[KytheVerifierSources].files]
        for input in dep.files.to_list():
            entries = ctx.actions.declare_file(
                ctx.label.name + input.basename + ".entries",
                sibling = ctx.outputs.entries,
            )
            intermediates += [entries]
            ctx.actions.run_shell(
                outputs = [entries],
                inputs = [input],
                tools = [ctx.executable.indexer] + ctx.files.tools,
                arguments = ([ctx.executable.indexer.path] +
                             [ctx.expand_location(o) for o in ctx.attr.opts] + [input.path, entries.path]),
                command = '("${@:1:${#@}-1}" || rm -f "${@:${#@}}") > "${@:${#@}}"',
                mnemonic = "IndexCompilation",
            )
    ctx.actions.run_shell(
        outputs = [ctx.outputs.entries],
        inputs = intermediates,
        command = '("${@:1:${#@}-1}" || rm -f "${@:${#@}}") | gzip -c > "${@:${#@}}"',
        mnemonic = "CompressEntries",
        arguments = ["cat"] + [i.path for i in intermediates] + [ctx.outputs.entries.path],
    )
    return [
        KytheVerifierSources(files = depset(transitive = sources)),
        KytheEntries(compressed = depset([ctx.outputs.entries]), files = depset(intermediates)),
    ]

index_compilation = rule(
    attrs = {
        "indexer": attr.label(
            mandatory = True,
            executable = True,
            cfg = "host",
        ),
        "opts": attr.string_list(),
        "tools": attr.label_list(
            cfg = "host",
            allow_files = True,
        ),
        "deps": attr.label_list(
            mandatory = True,
            allow_empty = False,
            allow_files = [".kzip"],
        ),
    },
    outputs = {
        "entries": "%{name}.entries.gz",
    },
    implementation = _index_compilation_impl,
)

def _verifier_test_impl(ctx):
    entries = []
    entries_gz = []
    sources = []
    for src in ctx.attr.srcs:
        if KytheVerifierSources in src:
            sources += [src[KytheVerifierSources].files]
            if KytheEntries in src:
                if src[KytheEntries].files:
                    entries += [src[KytheEntries].files]
                else:
                    entries_gz += [src[KytheEntries].compressed]
        else:
            sources += [depset(src.files)]

    for dep in ctx.attr.deps:
        # TODO(shahms): Allow specifying .entries files directly.
        if dep[KytheEntries].files:
            entries += [dep[KytheEntries].files]
        else:
            entries_gz += [dep[KytheEntries].compressed]

    # Flatten input lists
    entries = depset(transitive = entries).to_list()
    entries_gz = depset(transitive = entries_gz).to_list()
    sources = depset(transitive = sources).to_list()

    if not (entries or entries_gz):
        fail("Missing required entry stream input (check your deps!)")
    args = ctx.attr.opts + [src.short_path for src in sources]

    # If no dependency specifies KytheVerifierSources and
    # we aren't provided explicit sources, assume `--use_file_nodes`.
    if not sources and "--use_file_nodes" not in args:
        args += ["--use_file_nodes"]
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = ctx.outputs.executable,
        is_executable = True,
        substitutions = {
            "@ARGS@": " ".join(args),
            "@ENTRIES@": " ".join([e.short_path for e in entries]),
            "@ENTRIES_GZ@": " ".join([e.short_path for e in entries_gz]),
            # If failure is expected, invert the sense of the verifier return.
            "@INVERT@": "!" if not ctx.attr.expect_success else "",
            "@VERIFIER@": ctx.executable._verifier.short_path,
            "@WORKSPACE_NAME@": ctx.workspace_name,
        },
    )
    runfiles = ctx.runfiles(files = list(sources + entries + entries_gz) + [
        ctx.outputs.executable,
        ctx.executable._verifier,
    ], collect_data = True)
    return [
        DefaultInfo(runfiles = runfiles),
    ]

verifier_test = rule(
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            providers = [
                [KytheVerifierSources],
                [
                    KytheVerifierSources,
                    KytheEntries,
                ],
            ],
        ),
        # Arguably, "expect_failure" is more natural, but that
        # attribute is used by Skylark.
        "expect_success": attr.bool(default = True),
        "opts": attr.string_list(),
        "deps": attr.label_list(
            # TODO(shahms): Allow directly specifying sources/deps.
            #allow_files = [
            #    ".entries",
            #    ".entries.gz",
            #],
            providers = [KytheEntries],
        ),
        "_template": attr.label(
            default = Label("//tools/build_rules/verifier_test:verifier_test.sh.in"),
            allow_single_file = True,
        ),
        "_verifier": attr.label(
            default = Label("//kythe/cxx/verifier"),
            executable = True,
            cfg = "target",
        ),
    },
    test = True,
    implementation = _verifier_test_impl,
)

def _invoke(rulefn, name, **kwargs):
    """Invoke rulefn with name and kwargs, returning the label of the rule."""
    rulefn(name = name, **kwargs)
    return "//{}:{}".format(native.package_name(), name)

def kythe_integration_test(name, srcs, file_tickets, tags = [], size = "small"):
    entries = _invoke(
        atomize_entries,
        name = name + "_atomized_entries",
        testonly = True,
        srcs = [],
        file_tickets = file_tickets,
        tags = tags,
        deps = srcs,
    )
    return _invoke(
        verifier_test,
        name = name,
        size = size,
        opts = ["--ignore_dups"],
        tags = tags,
        deps = [entries],
    )
