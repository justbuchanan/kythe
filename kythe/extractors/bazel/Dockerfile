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

# FROM gcr.io/cloud-builders/bazel
# FROM ubuntu:18.04
FROM debian:buster

# # Install C++ compilers for cc_* rule support.
# RUN apt-get update && \
#     apt-get upgrade -y && \
#     apt-get install -y build-essential gcc clang-6.0 && \
#     apt-get clean

# # Create clang symlinks
# RUN ln -s /usr/bin/clang-6.0 /usr/bin/clang && \
#     ln -s /usr/bin/clang++-6.0 /usr/bin/clang++

RUN apt-get update && \
    apt-get install -y g++ && \
    apt-get clean


# Extract the Kythe release archive to /kythe
COPY kythe/release/kythe-v*.tar.gz /tmp/
RUN tar --no-same-owner -xzf /tmp/kythe-v*.tar.gz && \
    mv kythe-v*/ /kythe && \
    rm /tmp/kythe-v*.tar.gz

# Tools and configuration
ADD kythe/extractors/bazel/extract.sh /kythe/
ADD kythe/extractors/bazel/bazel_wrapper.sh /kythe/
ADD kythe/release/base/fix_permissions.sh /kythe/

# Bazelisk
ADD external/com_github_bazelbuild_bazelisk/linux_amd64_stripped/bazelisk /kythe/

# copied from gcr.io bazel image
# Store the Bazel outputs under /workspace so that the symlinks under bazel-bin
# (et al) are accessible to downstream build steps.
RUN mkdir -p /workspace
RUN echo 'startup --output_base=/workspace/.bazel' > ~/.bazelrc

RUN apt-get install -y git libeigen3-dev

ENV KYTHE_OUTPUT_DIRECTORY=/tmp/kythe

WORKDIR /workspace
RUN git clone https://github.com/justbuchanan/kythe_bazel_demo
WORKDIR /workspace/kythe_bazel_demo

# RUN /kythe/extract.sh build //...

# ENTRYPOINT ["/kythe/extract.sh"]
