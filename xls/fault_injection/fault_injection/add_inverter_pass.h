// Copyright 2020 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef XLS_PASSES_ADD_INVERTER_PASS_H_
#define XLS_PASSES_ADD_INVERTER_PASS_H_

#include "absl/status/statusor.h"
#include "xls/ir/function.h"
#include "xls/passes/optimization_pass.h"

namespace xls {

// Pass which performs constant folding. Every op with only literal operands is
// replaced by a equivalent literal. Runs DCE after constant folding.
class AddInverterPass : public OptimizationFunctionBasePass {
 public:
  AddInverterPass() : OptimizationFunctionBasePass("add_inverter", "Add inverter nodes") {}
  ~AddInverterPass() override = default;

 protected:
  absl::StatusOr<bool> RunOnFunctionBaseInternal(
      FunctionBase* f, const OptimizationPassOptions& options,
      PassResults* results) const override;
};

}  // namespace xls

#endif  // XLS_PASSES_ADD_INVERTER_PASS_H_