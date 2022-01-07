/*
 * Copyright 2021-2022 Hewlett Packard Enterprise Development LP
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

#ifndef CHPL_UAST_LOCAL_H
#define CHPL_UAST_LOCAL_H

#include "chpl/queries/Location.h"
#include "chpl/uast/BlockStyle.h"
#include "chpl/uast/Expression.h"
#include "chpl/uast/SimpleBlockLike.h"

namespace chpl {
namespace uast {


/**
  This class represents a local statement. For example:

  \rst
  .. code-block:: chapel

      // Example 1:
      const flag = true;
      local flag {
        var x = 0;
        writeln(x);
      }

      // Example 2:
      var x = 0;
      local do writeln(x);
  \endrst

 */
class Local final : public SimpleBlockLike {
 private:
  Local(ASTList children, int8_t condChildNum, BlockStyle blockStyle,
        int bodyChildNum,
        int numBodyStmts)
    : SimpleBlockLike(asttags::Local, std::move(children), blockStyle,
                      bodyChildNum,
                      numBodyStmts),
      condChildNum_(condChildNum) {
    assert(isExpressionASTList(children_));
  }

  bool contentsMatchInner(const ASTNode* other) const override {
    const Local* lhs = this;
    const Local* rhs = (const Local*) other;

    if (lhs->condChildNum_ != rhs->condChildNum_)
      return false;

    if (!lhs->simpleBlockLikeContentsMatchInner(rhs))
      return false;

    return true;
  }

  void markUniqueStringsInner(Context* context) const override {
    simpleBlockLikeMarkUniqueStringsInner(context);
  }

  int8_t condChildNum_;

 public:

  /**
    Create and return a local statement containing the passed statements.
  */
  static owned<Local> build(Builder* builder, Location loc,
                            BlockStyle blockStyle,
                            ASTList stmts);


  /**
    Create and return a local statement with the given condition and
    containing the passed statements.
  */
  static owned<Local> build(Builder* builder, Location loc,
                            owned<Expression> condition,
                            BlockStyle blockStyle,
                            ASTList stmts);

  /**
    Returns the condition of this local statement, or nullptr if there
    is none.
  */
  const Expression* condition() const {
    return condChildNum_ < 0 ? nullptr
      : (const Expression*)child(condChildNum_);
  }

};


} // end namespace uast
} // end namespace chpl

#endif
