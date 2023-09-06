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

# Optimization passes, pass managers.

package(
    default_visibility = ["//xls:xls_internal"],
    licenses = ["notice"],  # Apache 2.0
)


cc_library(
    name = "fault_injection_pass_pipeline",
    srcs = ["fault_injection_pass_pipeline.cc"],
    hdrs = ["fault_injection_pass_pipeline.h"],
    deps = [
        ":add_inverter_pass",
        "@com_google_absl//absl/status:statusor",
        "//xls/ir",
    ],
)

cc_library(
    name = "add_inverter_pass",
    srcs = ["add_inverter_pass.cc"],
    hdrs = ["add_inverter_pass.h"],
    deps = [
        "//xls/passes:optimization_pass",
        "@com_google_absl//absl/status:statusor",
        "//xls/common/logging",
        "//xls/common/status:status_macros",
        "//xls/interpreter:ir_interpreter",
        "//xls/ir",
        "//xls/ir:op",
    ],
)
