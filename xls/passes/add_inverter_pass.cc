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

#include "xls/passes/add_inverter_pass.h"

// #include <algorithm>
// #include <vector>

#include "absl/status/statusor.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/status_macros.h"
#include "xls/interpreter/function_interpreter.h"
#include "xls/ir/node_iterator.h"
#include "xls/ir/type.h"

namespace xls {

absl::StatusOr<bool> AddInverterPass::RunOnFunctionBaseInternal(
    FunctionBase* f, const OptimizationPassOptions& options,
    PassResults* results) const {
  bool changed = false;
  for (Node* node : TopoSort(f)) {
    // Add an inverter op after each op node.
    if (!node->Is<Literal>() && !TypeHasToken(node->GetType()) && // Check if the current node is NOT a literal value and if the node's type has a token type
        !OpIsSideEffecting(node->op()) && //  Check if the operation (op) of the node has any side effects
        std::all_of(node->operands().begin(), node->operands().end(),// This uses the std::all_of algorithm to check if all operands of the node are literals.
                    [](Node* o) { return o->Is<Literal>(); })) {
      XLS_VLOG(2) << "Adding Inverters to Constant Folding: " << *node;
      std::vector<Value> operand_values;
      for (Node* operand : node->operands()) {
        // Value val = operand->As<Literal>()->value();
        // Value inverted_val = ~val;
        // operand_values.push_back(inverted_val);
        operand_values.push_back(operand->As<Literal>()-> value()); // invert the merging values in constant folding
      }
      XLS_ASSIGN_OR_RETURN(Value result, InterpretNode(node, operand_values));
      XLS_RETURN_IF_ERROR(node->ReplaceUsesWithNew<Literal>(result).status());
      changed = true;
    }
  }

  return changed;
}

}  // namespace xls