/*
 * Copyright 2019 The Kythe Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Standalone extractor for text-format protobuf (textproto) files. Given a
// textproto file, builds a kzip containing it and all proto files it depends
// on.
//
// Usage:
//   export KYTHE_OUTPUT_FILE=foo.kzip
//   textproto_extractor foo.pbtxt
//   textproto_extractor foo.pbtxt -- --proto_path dir/with/proto/deps

#include "kythe/cxx/extractor/proto/proto_extractor.h"

#include <string>

#include "absl/strings/match.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_split.h"
#include "gflags/gflags.h"
#include "glog/logging.h"
#include "kythe/cxx/common/kzip_writer.h"
#include "kythe/cxx/extractor/textproto/textproto_schema.h"
#include "kythe/cxx/indexer/proto/search_path.h"
#include "kythe/proto/analysis.pb.h"

DEFINE_string(proto_message, "",
              "namespace-qualified message name for the textproto.");
DEFINE_string(proto_files, "",
              "A comma-separated list of proto files needed to fully define "
              "the textproto's schema.");

namespace kythe {
namespace lang_textproto {
namespace {

/// \brief Returns a kzip-based IndexWriter or dies.
IndexWriter OpenKzipWriterOrDie(absl::string_view path) {
  auto writer = KzipWriter::Create(path);
  CHECK(writer.ok()) << "Failed to open KzipWriter: " << writer.status();
  return std::move(*writer);
}

// Loads all data from a file or terminates the process.
std::string LoadFileOrDie(const std::string& file) {
  FILE* handle = fopen(file.c_str(), "rb");
  CHECK(handle != nullptr) << "Couldn't open input file " << file;
  CHECK_EQ(fseek(handle, 0, SEEK_END), 0) << "Couldn't seek " << file;
  long size = ftell(handle);
  CHECK_GE(size, 0) << "Bad size for " << file;
  CHECK_EQ(fseek(handle, 0, SEEK_SET), 0) << "Couldn't seek " << file;
  std::string content;
  content.resize(size);
  CHECK_EQ(fread(&content[0], size, 1, handle), 1) << "Couldn't read " << file;
  CHECK_NE(fclose(handle), EOF) << "Couldn't close " << file;
  return content;
}

}  // namespace

int main(int argc, char* argv[]) {
  google::InitGoogleLogging(argv[0]);
  gflags::SetUsageMessage(
      R"(Standalone extractor for the Kythe textproto indexer.
Creates a kzip containing the textproto and all proto files it depends on.

In order to make sense of the textproto, the extractor must know what proto
message describes it and what file that proto message comes from. This
information can be supplied with the --proto_message and --proto_files flags or
with specially-formatted comments in the textproto itself:

  # proto-file: some/file.proto
  # proto-message: some_namespace.MyMessage
  # proto-import: some/proto/with/extensions.proto

Examples:
  export KYTHE_OUTPUT_FILE=foo.kzip
  textproto_extractor foo.pbtxt
  textproto_extractor foo.pbtxt --proto_message MyMessage --proto_files foo.proto,bar.proto
  textproto_extractor foo.pbtxt --proto_message MyMessage --proto_files foo.proto -- --proto_path dir/with/my/deps")");
  gflags::ParseCommandLineFlags(&argc, &argv, /*remove_flags=*/true);
  std::vector<std::string> final_args(argv + 1, argv + argc);

  lang_proto::ProtoExtractor proto_extractor;
  proto_extractor.ConfigureFromEnv();

  // Parse --proto_path and -I args into a set of path substitution (search
  // paths).
  std::vector<std::string> textproto_args;
  ::kythe::lang_proto::ParsePathSubstitutions(
      final_args, &proto_extractor.path_substitutions, &textproto_args);

  // Load textproto.
  CHECK(textproto_args.size() == 1)
      << "Expected 1 textproto file, got " << textproto_args.size();
  std::string textproto_filename = textproto_args[0];
  const std::string textproto = LoadFileOrDie(textproto_filename);

  const char* output_file = getenv("KYTHE_OUTPUT_FILE");
  CHECK(output_file != nullptr)
      << "Please specify an output kzip file with the KYTHE_OUTPUT_FILE "
         "environment variable.";
  IndexWriter kzip_writer = OpenKzipWriterOrDie(output_file);

  // Info about the textproto's corresponding proto can come from comments in
  // the textproto itself or as command line flags to the extractor. Note that
  // if metadata is specified both in the textproto and via flags, flags take
  // precedence.
  TextprotoSchema schema = ParseTextprotoSchemaComments(textproto);
  std::vector<std::string> proto_filenames;
  if (!FLAGS_proto_files.empty()) {
    proto_filenames = absl::StrSplit(FLAGS_proto_files, ',');
  } else {
    proto_filenames.push_back(std::string(schema.proto_file));
    for (const auto& extra_import : schema.proto_imports) {
      proto_filenames.push_back(std::string(extra_import));
    }
  }
  if (!FLAGS_proto_message.empty()) {
    schema.proto_message = FLAGS_proto_message;
  }
  CHECK(!proto_filenames.empty())
      << "Proto file must be specified either with --proto_files flag or in "
         "textproto comments";
  CHECK(!schema.proto_message.empty())
      << "Proto message must be specified either with --proto_message flag or "
         "in textproto comments";

  // Call the proto extractor. This adds proto_file and all of its dependencies
  // into the kzip/unit, which we'll later need when indexing the textproto.
  proto::IndexedCompilation compilation;
  *compilation.mutable_unit() =
      proto_extractor.ExtractProtos(proto_filenames, &kzip_writer);

  // Replace the proto extractor's source file list with our textproto.
  compilation.mutable_unit()->clear_source_file();
  compilation.mutable_unit()->add_source_file(textproto_filename);

  // Re-build compilation unit's arguments list. Add --proto_message and any
  // protoc args.
  compilation.mutable_unit()->clear_argument();
  compilation.mutable_unit()->add_argument(textproto_filename);
  compilation.mutable_unit()->add_argument("--proto_message");
  compilation.mutable_unit()->add_argument(std::string(schema.proto_message));
  // Add protoc args.
  if (!proto_extractor.path_substitutions.empty()) {
    compilation.mutable_unit()->add_argument("--");
    for (auto& arg : lang_proto::PathSubstitutionsToArgs(
             proto_extractor.path_substitutions)) {
      compilation.mutable_unit()->add_argument(arg);
    }
  }

  // Add textproto file to kzip.
  {
    auto digest = kzip_writer.WriteFile(textproto);
    CHECK(digest.ok()) << digest.status();

    proto::CompilationUnit::FileInput* file_input =
        compilation.mutable_unit()->add_required_input();
    proto::VName vname =
        proto_extractor.vname_gen.LookupVName(textproto_filename);
    if (vname.corpus().empty()) {
      vname.set_corpus(proto_extractor.corpus);
    }
    *file_input->mutable_v_name() = std::move(vname);
    file_input->mutable_info()->set_path(textproto_filename);
    file_input->mutable_info()->set_digest(*digest);
  }

  // Save compilation unit.
  auto digest = kzip_writer.WriteUnit(compilation);
  CHECK(digest.ok()) << "Error writing unit to kzip: " << digest.status();
  CHECK(kzip_writer.Close().ok());

  return 0;
}

}  // namespace lang_textproto
}  // namespace kythe

int main(int argc, char* argv[]) {
  return kythe::lang_textproto::main(argc, argv);
}