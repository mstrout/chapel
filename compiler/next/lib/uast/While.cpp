/*
 * Copyright 2021 Hewlett Packard Enterprise Development LP
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "chpl/uast/While.h"

#include "chpl/uast/Builder.h"

namespace chpl {
namespace uast {


bool While::contentsMatchInner(const ASTNode* other) const {
  const While* lhs = this;
  const While* rhs = (const While*) other;
  return lhs->loopContentsMatchInner(rhs) &&
         lhs->conditionChildNum_ == rhs->conditionChildNum_;
}

void While::markUniqueStringsInner(Context* context) const {
  loopMarkUniqueStringsInner(context);
}

owned<While> While::build(Builder* builder, Location loc,
                      owned<Expression> condition,
                      ASTList stmts,
                      bool usesDo) {
  assert(condition.get() != nullptr);

  ASTList lst;
  int8_t conditionChildNum = lst.size();

  lst.push_back(std::move(condition));

  for (auto& stmt: stmts) {
    lst.push_back(std::move(stmt));
  }

  While* ret = new While(std::move(lst), conditionChildNum, usesDo);
  builder->noteLocation(ret, loc);
  return toOwned(ret);
}


} // namespace uast
} // namespace chpl
