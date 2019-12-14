#!/bin/bash

set -ex

# kzip create -uri "kythe://github.com/tensorflow/tensorflow?lang=bazel" \
#   -output=tfbazel.kzip \
#   $(bazelisk query 'buildfiles(//...)' \
#   | sed -E 's,^//:?,,' | sed 's,:,/,' | sed 's,$, \\,')


kzip create -uri "kythe://github.com/tensorflow/tensorflow?lang=bazel" \
  -output=tfbazel.kzip $(bazelisk query --output=xml 'buildfiles(//...)' | grep "source-file location" | sed -r 's,\s*<source-file location="([^:"]+).*,\1,' | xargs realpath --relative-to=$PWD | sed 's,^,--source_file=,')
