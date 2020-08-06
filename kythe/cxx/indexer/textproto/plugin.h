/*
 * Copyright 2020 The Kythe Authors. All rights reserved.
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

#ifndef KYTHE_CXX_INDEXER_TEXTPROTO_PLUGIN_H_
#define KYTHE_CXX_INDEXER_TEXTPROTO_PLUGIN_H_

#include <cstdio>
#include <string>

#include "absl/status/status.h"
#include "kythe/cxx/common/indexing/KytheGraphRecorder.h"
#include "kythe/proto/analysis.pb.h"

namespace kythe {
namespace lang_textproto {

// The plugin's interface to the indexer.
class PluginApi {
 public:
  PluginApi() = default;
  PluginApi(const PluginApi&) = delete;
  PluginApi& operator=(const PluginApi&) = delete;
  virtual ~PluginApi() = default;

  virtual proto::VName CreateAndAddAnchorNode(const proto::VName& file,
                                              int begin, int end) = 0;

  virtual proto::VName CreateAndAddAnchorNode(const proto::VName& file_vname,
                                              absl::string_view sp) = 0;

  virtual KytheGraphRecorder* recorder() = 0;

  virtual void EmitDiagnostic(const proto::VName& file_vname,
                              absl::string_view signature,
                              absl::string_view msg) = 0;

  virtual proto::VName VNameForRelPath(
      absl::string_view simplified_path) const = 0;
};

struct StringToken {
  // Parsed string value with escape codes resolved.
  std::string parsed_value;
  // The span of source text in the input. The underlying string that the view
  // references is owned by the `PluginApi`.
  absl::string_view source_text;
};

// Superclass for all plugins. A new plugin is instantated for each textproto
// handled by the indexer.
class Plugin {
 public:
  // Instantiate the plugin given the message resulting from parsing the
  // textproto file.
  Plugin(const google::protobuf::Message& proto) {}

  virtual ~Plugin() = default;

  // Main entrypoint for plugins. In the common case, `tokens` will contain a
  // single entry with the `parsed_value` and `source_text` fields equal in
  // string value. If string concatenation syntax is used, for example:
  //
  //   my_field: "abc" "def"
  //
  // There will be one StringToken per string "piece" ("abc" and "def" here). If
  // the string value contains escape codes, the parsed_value may be shorter
  // than the source_text as the multi-character escape code is replaced by a
  // single character.
  virtual absl::Status AnalyzeStringField(
      PluginApi* api, const proto::VName& file_vname,
      const google::protobuf::FieldDescriptor& field,
      std::vector<StringToken> tokens) = 0;
};

}  // namespace lang_textproto
}  // namespace kythe

#endif  // KYTHE_CXX_INDEXER_TEXTPROTO_PLUGIN_H_
