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

#include "xls/passes/adder_to_subtractor_pass.h"

// #include <algorithm>
// #include <vector>

#include "absl/status/statusor.h"
#include "xls/common/logging/logging.h"
#include "xls/common/status/status_macros.h"
#include "xls/interpreter/function_interpreter.h"
#include "xls/ir/node_iterator.h"
#include "xls/ir/nodes.h"
#include "xls/ir/op.h"

namespace xls {

absl::StatusOr<bool> AddInverterPass::RunOnFunctionBaseInternal(
    FunctionBase* f, const OptimizationPassOptions& options,
    PassResults* results) const {
  bool changed = false;
  std::vector<Node*> nodes;
  for (Node* node : TopoSort(f)) {
    nodes.push_back(node);
  }

  for (Node* node : nodes) {
    std::vector<Node*> users;
    for (Node* user : node->users()) {
      users.push_back(user);
    }
    if (!users.empty()) {
      XLS_ASSIGN_OR_RETURN(Node * inverter,
                           f->MakeNode<UnOp>(node->loc(), node, Op::kNeg));
      changed = true;
      for (Node* user : users) {
        user->ReplaceOperand(node, inverter);
      }
    }
  }

  return changed;
}

}  // namespace xls