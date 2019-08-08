#!/bin/bash
# Tests whether the indexer will read from kindex files.
set -ex
BASE_DIR="$PWD/kythe/cxx/indexer/cxx/testdata"
OUT_DIR="$TEST_TMPDIR"
VERIFIER="kythe/cxx/verifier/verifier"
INDEXER="kythe/cxx/indexer/cxx/indexer"
KINDEX_TOOL="kythe/cxx/tools/kindex_tool"
KZIP_TOOL="kythe/go/platform/tools/kzip/kzip"
TEST_KZIP="${OUT_DIR}/test.kzip"
REPO_TEST_KZIP="${OUT_DIR}/repo_test.kzip"
mkdir -p "${OUT_DIR}"

echo -e "class Header;\n" > main.h
echo -e "#include \"main.h\"\n#ifdef CMDARG\nclass Main;\n#else\n#error CMDARG unset--maybe we didn't see the CompilationUnit's arguments?\n#endif\n" > main.cc


"${KZIP_TOOL}" create -output "${TEST_KZIP}" \
    -uri "kythe://kythe?lang=c++#test_kindex" \
    -working_directory "/" \
    -source_file "main.cc" \
    -output_key "main.o" \
    -argument "unusedexecutable" \
    -argument "-DCMDARG" \
    -argument "main.cc" \
    -required_input "main.h" \
    -required_input "main.cc" 
    # "${BASE_DIR}/kindex_test.unit" \
    # "${BASE_DIR}/kindex_test.header" \
    # "${BASE_DIR}/kindex_test.main"
echo "CREATED KZIP: $TEST_KZIP"
"${INDEXER}" "${TEST_KZIP}" --ignore_unimplemented=false \
    > "${OUT_DIR}/kindex_test.entries"
cat "${OUT_DIR}/kindex_test.entries" \
    | "${VERIFIER}" --nocheck_for_singletons --show_goals --nofile_vnames \
      "${BASE_DIR}/kindex_test.verify"
# # The second test (which is useless unless the first succeeds) checks that
# # we handle relative paths.
# "${KINDEX_TOOL}" -assemble "${REPO_TEST_KZIP}" \
#     "${BASE_DIR}/kindex_repo_test.unit" \
#     "${BASE_DIR}/kindex_repo_test.header" \
#     "${BASE_DIR}/kindex_repo_test.header2" \
#     "${BASE_DIR}/kindex_repo_test.main"
# "${INDEXER}" "${REPO_TEST_KZIP}" --ignore_unimplemented=false \
#     > "${OUT_DIR}/kindex_repo_test.entries"
# cat "${OUT_DIR}/kindex_repo_test.entries" \
#     | "${VERIFIER}" --nocheck_for_singletons --nofile_vnames \
#       "${BASE_DIR}/kindex_repo_test.verify"
# # Finally, check that we can handle Windows paths.
# "${KINDEX_TOOL}" -assemble "${REPO_TEST_KZIP}" \
#     "${BASE_DIR}/windows_test.unit" \
#     "${BASE_DIR}/windows_test.header" \
#     "${BASE_DIR}/windows_test.main"
# "${INDEXER}" "${REPO_TEST_KZIP}" --ignore_unimplemented=false \
#     > "${OUT_DIR}/windows_test.entries"
# cat "${OUT_DIR}/windows_test.entries" \
#     | "${VERIFIER}" --nocheck_for_singletons --nofile_vnames \
#       "${BASE_DIR}/windows_test.verify"


# # TODO(justbuchanan): delete or convert to kzip
