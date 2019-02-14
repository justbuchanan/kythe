load(
    ":verifier_test.bzl",
    # "KytheVerifierSources",
    "extract",
    "index_compilation",
    "verifier_test",
)
load(
    "@io_kythe_lang_proto//kythe/cxx/indexer/proto/testdata:proto_verifier_test.bzl",
    "proto_extract_kzip",
)

def _invoke(rulefn, name, **kwargs):
    """Invoke rulefn with name and kwargs, returning the label of the rule."""
    rulefn(name = name, **kwargs)
    return "//{}:{}".format(native.package_name(), name)

def xlang_proto_verifier_test(
        name,
        srcs,
        build_annotated_generated_code_rule,
        genlang_extract_rule,
        genlang_indexer,
        size = "small",
        proto_srcs = [],
        tags = [],
        genlang_extractor_opts = [],
        verifier_opts = ["--ignore_dups"],
        genlang_extractor_deps = [],
        vnames_config = None,
        visibility = None):
    """Verify cross-language references between Proto and generated code (i.e. java, c++, etc).

    Args:
      name: Name of the test.
      size: Size of the test.
      tags: Test target tags.
      visibility: Visibility of the test target.
      srcs: The compilation's source files; each file's verifier goals will be checked
      proto_srcs: The compilation's proto source files; each file's verifier goals will be checked
      verifier_opts: List of options passed to the verifier tool
      vnames_config: Optional path to a VName configuration file
      TODO: more docs

    Returns: the label of the test.
    """
    proto_kzip = _invoke(
        proto_extract_kzip,
        name = name + "_proto_kzip",
        srcs = proto_srcs,
        tags = tags,
        visibility = visibility,
        vnames_config = vnames_config,
    )
    proto_entries = _invoke(
        index_compilation,
        name = name + "_proto_entries",
        testonly = True,
        indexer = "@io_kythe_lang_proto//kythe/cxx/indexer/proto:indexer",
        opts = ["--index_file"],
        tags = tags,
        visibility = visibility,
        deps = [proto_kzip],
    )

    gensrc = _invoke(
        build_annotated_generated_code_rule,
        name = name + "_gensrc",
        srcs = proto_srcs,
    )

    kzip = _invoke(
        genlang_extract_rule,
        name = name + "_genlang_kzip",
        srcs = srcs + [gensrc],
        opts = genlang_extractor_opts,
        tags = tags,
        visibility = visibility,
        vnames_config = vnames_config,
        deps = genlang_extractor_deps,
    )

    entries = _invoke(
        index_compilation,
        name = name + "_genlang_entries",
        testonly = True,
        indexer = genlang_indexer,
        opts = ["--verbose"],
        tags = tags,
        visibility = visibility,
        deps = [kzip],
    )
    return _invoke(
        verifier_test,
        name = name,
        size = size,
        srcs = [entries, proto_entries] + proto_srcs,
        opts = verifier_opts,
        tags = tags,
        visibility = visibility,
        deps = [entries],
    )
