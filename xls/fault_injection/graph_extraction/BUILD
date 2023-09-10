# Copyright 2020 The XLS Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@xls_pip_deps//:requirements.bzl", "requirement")

# pytype binary and test
load("@io_bazel_rules_closure//closure:defs.bzl", "closure_js_binary", "closure_js_library")
load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//xls/examples:list_filegroup_files.bzl", "list_filegroup_files")
# js_binary used in this file
# cc_proto_library is used in this file

package(
    default_visibility = ["//xls:xls_internal"],
    licenses = ["notice"],  # Apache 2.0
)

filegroup(
    name = "ir_examples",
    srcs = [
        "//xls/dslx/stdlib:ir_examples",
        "//xls/examples:ir_examples",
        # "//xls/tutorial"
    ],
)

list_filegroup_files(
    name = "ir_examples_file_list",
    src = ":ir_examples",
    out = "ir_examples_file_list.txt",
)

py_binary(
    name = "graph_extraction",
    srcs = ["graph_extraction.py"],
    data = [
        "ir_examples_file_list.txt",
        # "ir_graph.css",
        # "templates/splash.tmpl",
        # "third_party_js.txt",
        # ":ir_examples",
        # ":js_compiled",
        "//xls/tools:opt_main",
        # "//xls/tutorial:simple_add.ir",
    ],
    python_version = "PY3",
    srcs_version = "PY3",
    deps = [
        # requirement("Flask"),
        # requirement("Jinja2"),
        # requirement("click"),
        # requirement("itsdangerous"),
        # requirement("MarkupSafe"),
        # requirement("Werkzeug"),
        "//xls/common:runfiles",
        "//xls/common/python:init_xls",
        "//xls/visualization/ir_viz/python:ir_to_json",
        # "//xls/visualization/ir_viz:ir_to_json",
        "@com_google_absl_py//absl:app",
        "@com_google_absl_py//absl/flags",
    ],
)
