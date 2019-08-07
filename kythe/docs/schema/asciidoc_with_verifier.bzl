load("//kythe/docs:asciidoc.bzl", "asciidoc")

def asciidoc_with_verifier(name, src, tags = None):
    """Invoke the asciidoc tool on the specified source file, filtering examples to
    be passed to the verifier. If the verifier does not succeed, the build will fail.
    """

    asciidoc(
        name = name,
        src = src,
        confs = ["kythe-filter.conf"],
        example_script = ":example_sh",
        data = [
            "example-clike.sh",
            "example-cxx.sh",
            "example-objc.sh",
            "example-dot.sh",
            "example-go.sh",
            "example-java.sh",
            "java-schema-file-data-template.FileData",
            "java-schema-unit-template.CompilationUnit",
            "//kythe/cxx/indexer/cxx:indexer",
            "//kythe/cxx/tools:kindex_tool",
            "//kythe/go/indexer/cmd/go_example:go_example",
            "//kythe/go/platform/tools/shasum_tool",
            "//kythe/java/com/google/devtools/kythe/analyzers/java:indexer",
            "//kythe/cxx/verifier",
        ],
        tags = tags,
    )

def build_example_sh():
    """This rule must be executed once to set up the genrule used to plug in tool
    paths to the verifier scripts.
    """
    tools = {
        "CXX_INDEXER_BIN": "//kythe/cxx/indexer/cxx:indexer",
        "GO_INDEXER_BIN": "//kythe/go/indexer/cmd/go_example:go_example",
        "JAVA_INDEXER_BIN": "//kythe/java/com/google/devtools/kythe/analyzers/java:indexer",
        "KINDEX_TOOL_BIN": "//kythe/cxx/tools:kindex_tool", # TODO(justbuchanan): remove
        "SHASUM_TOOL": "//kythe/go/platform/tools/shasum_tool:shasum_tool",
        "VERIFIER_BIN": "//kythe/cxx/verifier",
    }
    fixes = [
        "-e '/^export %s=/{i\\\n_p=($(locations %s))\ns#$$#\"$$ROOT/$${_p[0]}\"#\n}'" % (key, target)
        for (key, target) in tools.items()
    ]
    native.genrule(
        name = "example_sh",
        srcs = ["example-base.sh"] + tools.values(),
        outs = ["example.sh"],
        cmd = " ".join(["sed"] + fixes + ["$(location example-base.sh)", ">$@"]),
    )
