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

#include "return-type-inference.h"

#include "chpl/framework/ErrorMessage.h"
#include "chpl/framework/UniqueString.h"
#include "chpl/framework/global-strings.h"
#include "chpl/framework/query-impl.h"
#include "chpl/parsing/parsing-queries.h"
#include "chpl/resolution/ResolvedVisitor.h"
#include "chpl/resolution/can-pass.h"
#include "chpl/resolution/disambiguation.h"
#include "chpl/resolution/intents.h"
#include "chpl/resolution/resolution-queries.h"
#include "chpl/resolution/scope-queries.h"
#include "chpl/types/all-types.h"
#include "chpl/uast/all-uast.h"

#include "Resolver.h"

#include <cstdio>
#include <set>
#include <string>
#include <tuple>
#include <unordered_map>
#include <utility>
#include <vector>

namespace chpl {
namespace resolution {


using namespace uast;
using namespace types;

// forward declarations
static QualifiedType adjustForReturnIntent(uast::Function::ReturnIntent ri,
                                           QualifiedType retType);


// Get a Type for an AggregateDecl
// poiScope, instantiatedFrom are nullptr if not instantiating
const CompositeType* helpGetTypeForDecl(Context* context,
                                        const AggregateDecl* ad,
                                        const SubstitutionsMap& substitutions,
                                        const PoiScope* poiScope,
                                        const Type* instantiatedFrom) {

  CHPL_ASSERT(ad);

  // Filter out substitutions that aren't fields within 'ad'.
  // In particular, there might be substitutions to do with a parent class.
  SubstitutionsMap filteredSubs;
  for (const auto& pair : substitutions) {
    if (ad->id().contains(pair.first)) {
      filteredSubs.insert(pair);
    }
  }

  if (filteredSubs.empty()) {
    instantiatedFrom = nullptr;
  }

  const CompositeType* ret = nullptr;

  if (const Class* c = ad->toClass()) {
    const BasicClassType* parentClassType = nullptr;
    if (const AstNode* parentClassExpr = c->parentClass()) {
      // Resolve the parent class type expression
      ResolutionResultByPostorderID r;
      auto visitor =
        Resolver::createForParentClass(context, c,
                                       substitutions,
                                       poiScope, r);
      parentClassExpr->traverse(visitor);

      QualifiedType qt = r.byAst(parentClassExpr).type();
      if (auto t = qt.type()) {
        if (auto bct = t->toBasicClassType())
          parentClassType = bct;
        else if (auto ct = t->toClassType())
          parentClassType = ct->basicClassType();
      }
      if (qt.isType() && parentClassType != nullptr) {
        // OK
      } else {
        context->error(parentClassExpr, "invalid parent class expression");
        parentClassType = BasicClassType::getObjectType(context);
      }
    } else {
      parentClassType = BasicClassType::getObjectType(context);
    }

    const BasicClassType* insnFromBct = nullptr;
    if (instantiatedFrom != nullptr) {
      if (auto bct = instantiatedFrom->toBasicClassType())
        insnFromBct = bct;
      else if (auto ct = instantiatedFrom->toClassType())
        insnFromBct = ct->basicClassType();
      else
        CHPL_ASSERT(false && "unexpected instantiatedFrom type");
    }


    if (!parentClassType->isObjectType() && !substitutions.empty()) {
      // recompute the parent class type with substitutions
      auto parentAst = parsing::idToAst(context, parentClassType->id());
      CHPL_ASSERT(parentAst);
      auto parentAd = parentAst->toAggregateDecl();
      CHPL_ASSERT(parentAd);
      auto got = helpGetTypeForDecl(context,
                                    parentAd,
                                    substitutions,
                                    poiScope,
                                    parentClassType);
      auto gotBct = got->toBasicClassType();
      CHPL_ASSERT(gotBct);
      parentClassType = gotBct;
    }

    ret = BasicClassType::get(context, c->id(), c->name(),
                              parentClassType,
                              insnFromBct, std::move(filteredSubs));

  } else if (auto r = ad->toRecord()) {
    if (r->id().symbolPath() == "ChapelDomain._domain") {
      ret = DomainType::getGenericDomainType(context);
      // TODO: update this to call a method on ArrayType to get the id or path
    } else if (r->id().symbolPath() == "ChapelArray._array") {
      ret = ArrayType::getGenericArrayType(context);
    } else {
      const RecordType* insnFromRec = nullptr;
      if (instantiatedFrom != nullptr) {
        if (auto rec = instantiatedFrom->toRecordType())
          insnFromRec = rec;
        else
          CHPL_ASSERT(false && "unexpected instantiatedFrom type");
      }

      ret = RecordType::get(context, r->id(), r->name(),
                            insnFromRec, std::move(filteredSubs));
    }

  } else if (auto u = ad->toUnion()) {
    const UnionType* insnFromUni = nullptr;
    if (instantiatedFrom != nullptr) {
      if (auto uni = instantiatedFrom->toUnionType())
        insnFromUni = uni;
      else
        CHPL_ASSERT(false && "unexpected instantiatedFrom type");
    }

    ret = UnionType::get(context, u->id(), u->name(),
                         insnFromUni, std::move(filteredSubs));

  } else {
    CHPL_ASSERT(false && "case not handled");
  }

  return ret;
}

// TOOD:
// This code will be duplicating a lot of stuff in VarScopeVisitor, but it's
// different enough that I don't know how to proceed. I'm certain that there's
// a general way to make all these traversals work.

struct ReturnInferenceFrame;
struct ReturnInferenceSubFrame {
  // The AST node whose frame should be saved into this sub-frame
  const AstNode* astNode = nullptr;
  // The frame associated with the given AST node.
  owned<ReturnInferenceFrame> frame = nullptr;
  // Whether this sub-frame should be skipped when combining sub-results.
  // Occurrs in particular when a branch is known statically not to occur.
  bool skip = false;

  ReturnInferenceSubFrame(const AstNode* node) : astNode(node) {}
};

struct ReturnInferenceFrame {
  const AstNode* scopeAst = nullptr;
  bool returnsOrThrows = false;
  std::vector<ReturnInferenceSubFrame> subFrames;

  ReturnInferenceFrame(const AstNode* node) : scopeAst(node) {}
};

struct ReturnTypeInferrer {
  using RV = ResolvedVisitor<ReturnTypeInferrer>;

  // input
  Context* context;
  const AstNode* astForErr;
  Function::ReturnIntent returnIntent;
  const Type* declaredReturnType;

  // intermediate information
  std::vector<owned<ReturnInferenceFrame>> returnFrames;

  // output
  std::vector<QualifiedType> returnedTypes;

  ReturnTypeInferrer(Context* context,
                     const Function* fn,
                     const Type* declaredReturnType)
    : context(context),
      astForErr(fn),
      returnIntent(fn->returnIntent()),
      declaredReturnType(declaredReturnType) {
  }

  void process(const uast::AstNode* symbol,
               ResolutionResultByPostorderID& byPostorder);

  void checkReturn(const AstNode* inExpr, const QualifiedType& qt);
  void noteVoidReturnType(const AstNode* inExpr);
  void noteReturnType(const AstNode* expr, const AstNode* inExpr, RV& rv);

  QualifiedType returnedType();

  ReturnInferenceSubFrame& currentThenFrame();
  ReturnInferenceSubFrame& currentElseFrame();

  void enterScope(const uast::AstNode* node);
  void exitScope(const uast::AstNode* node);

  bool markReturnOrThrow();

  bool enter(const Function* fn, RV& rv);
  void exit(const Function* fn, RV& rv);

  bool enter(const Conditional* cond, RV& rv);
  void exit(const Conditional* cond, RV& rv);

  bool enter(const Return* ret, RV& rv);
  void exit(const Return* ret, RV& rv);

  bool enter(const Yield* ret, RV& rv);
  void exit(const Yield* ret, RV& rv);

  bool enter(const AstNode* ast, RV& rv);
  void exit(const AstNode* ast, RV& rv);
};

void ReturnTypeInferrer::process(const uast::AstNode* symbol,
                                 ResolutionResultByPostorderID& byPostorder) {
  ResolvedVisitor<ReturnTypeInferrer> rv(context, symbol, *this, byPostorder);
  symbol->traverse(rv);
}

void ReturnTypeInferrer::checkReturn(const AstNode* inExpr,
                                     const QualifiedType& qt) {
  if (!qt.type()) {
    return;
  }
  if (qt.type()->isVoidType()) {
    if (returnIntent == Function::REF) {
      context->error(inExpr, "Cannot return void with ref return intent");
    } else if (returnIntent == Function::PARAM) {
      context->error(inExpr, "Cannot return void with param return intent");
    } else if (returnIntent == Function::TYPE) {
      context->error(inExpr, "Cannot return void with type return intent");
    }
  } else {
    bool ok = true;
    if ((qt.isType() || qt.isParam()) &&
        (returnIntent == Function::CONST_REF ||
         returnIntent == Function::REF)) {
      ok = false;
    } else if (returnIntent == Function::TYPE && !qt.isType()) {
      ok = false;
    } else if (returnIntent == Function::PARAM && !qt.isParam()) {
      ok = false;
    }
    if (!ok) {
      context->error(inExpr, "cannot return it with provided return intent");
    }
  }
}

void ReturnTypeInferrer::noteVoidReturnType(const AstNode* inExpr) {
  auto voidType = QualifiedType(QualifiedType::CONST_VAR, VoidType::get(context));
  returnedTypes.push_back(voidType);

  checkReturn(inExpr, voidType);
}
void ReturnTypeInferrer::noteReturnType(const AstNode* expr,
                                        const AstNode* inExpr,
                                        RV& rv) {
  QualifiedType qt = rv.byAst(expr).type();

  QualifiedType::Kind kind = qt.kind();
  const Type* type = qt.type();

  // Functions that return tuples need to return
  // a value tuple (for value returns and type returns)
  // or a reference to a value tuple (for ref/const ref returns)
  if (type && type->isTupleType()) {
    auto tt = type->toTupleType();
    type = tt->toValueTuple(context);
    qt = QualifiedType(kind, type);
  }

  checkReturn(inExpr, qt);
  returnedTypes.push_back(std::move(qt));
}

QualifiedType ReturnTypeInferrer::returnedType() {
  if (returnedTypes.size() == 0) {
    return QualifiedType(QualifiedType::CONST_VAR, VoidType::get(context));
  } else {
    auto retType = commonType(context, returnedTypes,
                              (QualifiedType::Kind) returnIntent);
    if (!retType) {
      // Couldn't find common type, so return type is incorrect.
      context->error(astForErr, "could not determine return type for function");
      retType = QualifiedType(QualifiedType::UNKNOWN, ErroneousType::get(context));
    }
    auto adjType = adjustForReturnIntent(returnIntent, *retType);
    return adjType;
  }
}

ReturnInferenceSubFrame& ReturnTypeInferrer::currentThenFrame() {
  CHPL_ASSERT(returnFrames.size() > 0);
  auto& topFrame = returnFrames.back();
  CHPL_ASSERT(topFrame->scopeAst->isConditional());
  return topFrame->subFrames[0];
}
ReturnInferenceSubFrame& ReturnTypeInferrer::currentElseFrame() {
  CHPL_ASSERT(returnFrames.size() > 0);
  auto& topFrame = returnFrames.back();
  CHPL_ASSERT(topFrame->scopeAst->isConditional());
  return topFrame->subFrames[1];
}

void ReturnTypeInferrer::enterScope(const uast::AstNode* node) {
  if (!createsScope(node->tag())) return;

  returnFrames.push_back(toOwned(new ReturnInferenceFrame(node)));
  auto& newFrame = returnFrames.back();

  if (auto condNode = node->toConditional()) {
    newFrame->subFrames.emplace_back(condNode->thenBlock());
    newFrame->subFrames.emplace_back(condNode->elseBlock());
  } else if (auto tryNode = node->toTry()) {
    for (auto clause : tryNode->handlers()) {
      newFrame->subFrames.emplace_back(clause);
    }
  }
}

void ReturnTypeInferrer::exitScope(const uast::AstNode* node) {
  if (!createsScope(node->tag())) return;

  CHPL_ASSERT(returnFrames.size() > 0);
  auto poppingFrame = std::move(returnFrames.back());
  CHPL_ASSERT(poppingFrame->scopeAst == node);
  returnFrames.pop_back();

  bool parentReturnsOrThrows = poppingFrame->returnsOrThrows;

  if (poppingFrame->scopeAst->isLoop()) {
    // Could have while true { break; return; }, so do not propagate
    // returns.
    parentReturnsOrThrows = false;
  }

  // Integrate sub-frame information.
  if (poppingFrame->subFrames.size() > 0) {
    bool allReturnOrThrow = true;
    for (auto& subFrame : poppingFrame->subFrames) {
      if (subFrame.skip) continue;

      if (subFrame.frame == nullptr || !subFrame.frame->returnsOrThrows) {
        allReturnOrThrow = false;
        break;
      }
    }

    if (poppingFrame->scopeAst->isTry()) {
      // The sub-frames of try/catch nodes are just the catches, but they
      // aren't the only thing that needs to return: the try itself
      // should return too.
      //
      // Use & here because parentOrThrows is already set to try's return
      // state earlier.
      parentReturnsOrThrows &= allReturnOrThrow;
    } else {
      parentReturnsOrThrows = allReturnOrThrow;
    }

  }

  if (returnFrames.size() > 0) {
    // Might we become a sub-frame in another frame?
    auto& parentFrame = returnFrames.back();
    bool storedAsSubFrame = false;

    for (auto& subFrame : parentFrame->subFrames) {
      if (subFrame.astNode == node) {
        subFrame.frame = std::move(poppingFrame);
        storedAsSubFrame = true;
      }
    }

    if (!storedAsSubFrame) {
      parentFrame->returnsOrThrows |= parentReturnsOrThrows;
    }
  }
}

bool ReturnTypeInferrer::markReturnOrThrow() {
  if (returnFrames.empty()) return false;
  auto& topFrame = returnFrames.back();
  bool oldValue = topFrame->returnsOrThrows;
  topFrame->returnsOrThrows = true;
  return oldValue;
}

bool ReturnTypeInferrer::enter(const Function* fn, RV& rv) {
  return false;
}
void ReturnTypeInferrer::exit(const Function* fn, RV& rv) {
}


bool ReturnTypeInferrer::enter(const Conditional* cond, RV& rv) {
  enterScope(cond);
  auto condition = cond->condition();
  CHPL_ASSERT(condition != nullptr);
  const ResolvedExpression& r = rv.byAst(condition);
  if (r.type().isParamTrue()) {
    auto then = cond->thenBlock();
    CHPL_ASSERT(then != nullptr);
    then->traverse(rv);
    // It doesn't matter if we don't return in the else frame, since it's
    // compiled out.
    currentElseFrame().skip = true;
    return false;
  } else if (r.type().isParamFalse()) {
    auto else_ = cond->elseBlock();
    if (else_) {
      else_->traverse(rv);
    }
    // It doesn't matter if we don't return in the then frame, since it's
    // compiled out.
    currentThenFrame().skip = true;
    return false;
  }
  return true;
}
void ReturnTypeInferrer::exit(const Conditional* cond, RV& rv) {
  exitScope(cond);
}

bool ReturnTypeInferrer::enter(const Return* ret, RV& rv) {
  if (markReturnOrThrow()) {
    // If it's statically known that we've already encountered a return or yield,
    // we can safely ignore subsequent returns.
  } else if (const AstNode* expr = ret->value()) {
    noteReturnType(expr, ret, rv);
  } else {
    noteVoidReturnType(ret);
  }
  return false;
}
void ReturnTypeInferrer::exit(const Return* ret, RV& rv) {
}

bool ReturnTypeInferrer::enter(const Yield* ret, RV& rv) {
  if (markReturnOrThrow()) {
    // If it's statically known that we've already encountered a return or yield,
    // we can safely ignore subsequent returns.
  } else {
    noteReturnType(ret->value(), ret, rv);
  }
  return false;
}
void ReturnTypeInferrer::exit(const Yield* ret, RV& rv) {
}

bool ReturnTypeInferrer::enter(const AstNode* ast, RV& rv) {
  enterScope(ast);
  return true;
}
void ReturnTypeInferrer::exit(const AstNode* ast, RV& rv) {
  exitScope(ast);
}


// For a class type construction, returns a BasicClassType
static const Type* const&
returnTypeForTypeCtorQuery(Context* context,
                           const TypedFnSignature* sig,
                           const PoiScope* poiScope) {
  QUERY_BEGIN(returnTypeForTypeCtorQuery, context, sig, poiScope);

  const UntypedFnSignature* untyped = sig->untyped();

  const Type* result = nullptr;

  // handle type construction
  const AggregateDecl* ad = nullptr;
  if (!untyped->id().isEmpty())
    if (auto ast = parsing::idToAst(context, untyped->id()))
      ad = ast->toAggregateDecl();

  if (ad) {
    // compute instantiatedFrom
    const CompositeType* instantiatedFrom = nullptr;
    if (sig->instantiatedFrom()) {
      const Type* t = initialTypeForTypeDecl(context, ad->id());
      CHPL_ASSERT(t);

      // ignore decorators etc for finding instantiatedFrom
      if (auto ct = t->toClassType())
        t = ct->basicClassType();

      instantiatedFrom = t->toCompositeType();
      CHPL_ASSERT(instantiatedFrom);
    }

    // compute the substitutions
    SubstitutionsMap subs;

    if (instantiatedFrom != nullptr) {
      int nFormals = sig->numFormals();
      for (int i = 0; i < nFormals; i++) {
        const Decl* formalDecl = untyped->formalDecl(i);
        const QualifiedType& formalType = sig->formalType(i);
        // Note that the formalDecl should already be a fieldDecl
        // based on typeConstructorInitialQuery.
        bool hasInitExpression = false;
        if (auto vd = formalDecl->toVarLikeDecl())
          if (vd->initExpression() != nullptr)
            hasInitExpression = true;

        if (formalType.type()->isAnyType() && !hasInitExpression) {
          // Ignore this substitution - easier to just leave it out
          // of the map entirely.
          // Note that we explicitly put a sub for AnyType for generics
          // with default, where the default is not used. E.g.
          //    record R { type t = int; }
          //    type RR = R(?);
          //    var x: RR;
          // is a compilation error because x has generic type.
          // In order to support that pattern, we need to be able to
          // represent that RR is a version of R where it's not behaving
          // as generic-with-default and substituting in AnyType does that.
        } else {
          subs.insert({formalDecl->id(), formalType});
        }
      }
    }

    // get a type using the substitutions
    const CompositeType* theType = helpGetTypeForDecl(context, ad,
                                                      subs,
                                                      poiScope,
                                                      instantiatedFrom);

    result = theType;

  } else {
    // built-in type construction should be handled
    // by resolveFnCallSpecialType and not reach this point.
    CHPL_ASSERT(false && "case not handled");
  }

  return QUERY_END(result);
}

static QualifiedType computeTypeOfField(Context* context,
                                        const Type* t,
                                        ID fieldId) {
  if (const CompositeType* ct = t->getCompositeType()) {
    // Figure out the parent MultiDecl / TupleDecl
    ID declId = parsing::idToContainingMultiDeclId(context, fieldId);

    // Resolve the type of that field (or MultiDecl/TupleDecl)
    const auto& fields = resolveFieldDecl(context, ct, declId,
                                          DefaultsPolicy::IGNORE_DEFAULTS);
    int n = fields.numFields();
    for (int i = 0; i < n; i++) {
      if (fields.fieldDeclId(i) == fieldId) {
        return fields.fieldType(i);
      }
    }
  }

  CHPL_ASSERT(false && "should not be reachable");
  return QualifiedType(QualifiedType::VAR, ErroneousType::get(context));
}

static QualifiedType adjustForReturnIntent(uast::Function::ReturnIntent ri,
                                           QualifiedType retType) {

  QualifiedType::Kind kind = (QualifiedType::Kind) ri;
  // adjust default / const return intent to 'var'
  if (kind == QualifiedType::DEFAULT_INTENT ||
      kind == QualifiedType::VAR) {
    kind = QualifiedType::CONST_VAR;
  }
  return QualifiedType(kind, retType.type(), retType.param());
}


struct CountReturns {
  // input
  Context* context;

  // output
  int nReturnsWithValue = 0;
  int nReturnsWithoutValue = 0;
  const AstNode* firstWithValue = nullptr;
  const AstNode* firstWithoutValue = nullptr;

  CountReturns(Context* context)
    : context(context) {
  }

  void countWithValue(const AstNode* ast);
  void countWithoutValue(const AstNode* ast);

  bool enter(const Function* fn);
  void exit(const Function* fn);

  bool enter(const Return* ret);
  void exit(const Return* ret);

  bool enter(const Yield* ret);
  void exit(const Yield* ret);

  bool enter(const AstNode* ast);
  void exit(const AstNode* ast);
};

void CountReturns::countWithValue(const AstNode* ast) {
  if (firstWithValue == nullptr) {
    firstWithValue = ast;
  }
  nReturnsWithValue++;
}

void CountReturns::countWithoutValue(const AstNode* ast) {
  if (firstWithoutValue == nullptr) {
    firstWithoutValue = ast;
  }
  nReturnsWithoutValue++;
}

bool CountReturns::enter(const Function* fn) {
  return false;
}
void CountReturns::exit(const Function* fn) {
}

bool CountReturns::enter(const Return* ret) {
  if (ret->value() != nullptr) {
    countWithValue(ret);
  } else {
    countWithoutValue(ret);
  }
  return false;
}
void CountReturns::exit(const Return* ret) {
}

bool CountReturns::enter(const Yield* ret) {
  if (ret->value() != nullptr) {
    countWithValue(ret);
  } else {
    countWithoutValue(ret);
  }
  return false;
}
void CountReturns::exit(const Yield* ret) {
}

bool CountReturns::enter(const AstNode* ast) {
  return true;
}
void CountReturns::exit(const AstNode* ast) {
}

// vs. just returning 'void'
static const bool& fnAstReturnsNonVoid(Context* context, ID fnId) {
  QUERY_BEGIN(fnAstReturnsNonVoid, context, fnId);

  bool result = false;

  const AstNode* ast = parsing::idToAst(context, fnId);
  const Function* fn = ast->toFunction();
  CHPL_ASSERT(fn);

  CountReturns cr(context);
  fn->body()->traverse(cr);

  result = (cr.nReturnsWithValue > 0);

  if (cr.nReturnsWithValue > 0 && cr.nReturnsWithoutValue > 0) {
    // TODO: make this a real error message
    context->error(cr.firstWithoutValue, "Mix of return types");
  }

  if (cr.nReturnsWithValue > 0 &&
      (fn->name() == USTR("init") || fn->name() == USTR("init="))) {
    context->error(cr.firstWithValue, "initializers can only return 'void'");
  }

  return QUERY_END(result);
}

// returns 'true' if it was a case handled here & sets 'result' in that case
// returns 'false' if it needs to be computed with a ResolvedVisitor traversal
static bool helpComputeReturnType(Context* context,
                                  const TypedFnSignature* sig,
                                  const PoiScope* poiScope,
                                  QualifiedType& result) {
  const UntypedFnSignature* untyped = sig->untyped();

  if (untyped->idIsFunction() && sig->needsInstantiation()) {
    // if it needs instantiation, we don't know the return type yet.
    result = QualifiedType(QualifiedType::UNKNOWN, UnknownType::get(context));
    return true;
  } else if (untyped->idIsFunction()) {
    const AstNode* ast = parsing::idToAst(context, untyped->id());
    const Function* fn = ast->toFunction();
    CHPL_ASSERT(fn);

    if (const AstNode* retType = fn->returnType()) {
      // resolve the return type
      ResolutionResultByPostorderID resolutionById;
      auto visitor = Resolver::createForFunction(context, fn, poiScope, sig,
                                                 resolutionById);
      retType->traverse(visitor);
      result = resolutionById.byAst(retType).type();

      auto g = getTypeGenericity(context, result.type());
      if (g == Type::CONCRETE) {
        result = adjustForReturnIntent(fn->returnIntent(), result);
        return true;
      }
    }

    // if there are no returns with a value, use void return type
    if (fnAstReturnsNonVoid(context, ast->id()) == false) {
      result = QualifiedType(QualifiedType::CONST_VAR, VoidType::get(context));
      return true;
    }

    // otherwise, need to use visitor to get the return type
    return false;

  } else if (untyped->isTypeConstructor()) {
    const Type* t = returnTypeForTypeCtorQuery(context, sig, poiScope);

    // for a 'class C' declaration, the above query returns a BasicClassType,
    // but 'C' normally means a generic-management non-nil C
    // so adjust the result.
    if (untyped->idIsClass()) {
      auto bct = t->toBasicClassType();
      CHPL_ASSERT(bct);
      auto dec = ClassTypeDecorator(ClassTypeDecorator::GENERIC_NONNIL);
      t = ClassType::get(context, bct, /*manager*/ nullptr, dec);
    }

    result = QualifiedType(QualifiedType::TYPE, t);
    return true;

  // if method call and the receiver points to a composite type definition,
  // then it's some sort of compiler-generated method
  } else if (untyped->isCompilerGenerated()) {
    if (untyped->name() == USTR("init")) {
      result = QualifiedType(QualifiedType::CONST_VAR,
                             VoidType::get(context));
      return true;
    } else if (untyped->idIsField() && untyped->isMethod()) {
      // method accessor - compute the type of the field
      QualifiedType ft = computeTypeOfField(context,
                                            sig->formalType(0).type(),
                                            untyped->id());
      if (ft.isType() || ft.isParam()) {
        // return the type as-is (preserving param/type-ness)
        result = ft;
      } else if (ft.isConst()) {
        // return a const ref
        result = QualifiedType(QualifiedType::CONST_REF, ft.type());
      } else {
        // return a ref
        result = QualifiedType(QualifiedType::REF, ft.type());
      }
      return true;
    } else if (untyped->isMethod() && sig->formalType(0).type()->isDomainType()) {
      auto dt = sig->formalType(0).type()->toDomainType();

      if (untyped->name() == "idxType") {
        result = dt->idxType();
      } else if (untyped->name() == "rank") {
        // Can't use `RankType::rank` because `D.rank` is defined for associative
        // domains, even though they don't have a matching substitution.
        result = QualifiedType(QualifiedType::PARAM,
                               IntType::get(context, 64),
                               IntParam::get(context, dt->rankInt()));
      } else if (untyped->name() == "stridable") {
        result = dt->stridable();
      } else if (untyped->name() == "parSafe") {
        result = dt->parSafe();
      } else if (untyped->name() == "isRectangular") {
        auto val = BoolParam::get(context, dt->kind() == DomainType::Kind::Rectangular);
        auto type = BoolType::get(context, 0);
        result = QualifiedType(QualifiedType::PARAM, type, val);
      } else if (untyped->name() == "isAssociative") {
        auto val = BoolParam::get(context, dt->kind() == DomainType::Kind::Associative);
        auto type = BoolType::get(context, 0);
        result = QualifiedType(QualifiedType::PARAM, type, val);
      } else {
        CHPL_ASSERT(false && "unhandled compiler-generated domain method");
        return true;
      }
      return true;
    } else if (untyped->isMethod() && sig->formalType(0).type()->isArrayType()) {
      auto at = sig->formalType(0).type()->toArrayType();

      if (untyped->name() == "domain") {
        result = QualifiedType(QualifiedType::CONST_REF, at->domainType().type());
      } else if (untyped->name() == "eltType") {
        result = at->eltType();
      } else {
        CHPL_ASSERT(false && "unhandled compiler-generated array method");
      }

      return true;
    } else {
      CHPL_ASSERT(false && "unhandled compiler-generated method");
      return true;
    }
  } else {
    CHPL_ASSERT(false && "case not handled");
    return true;
  }

  return false;
}

const QualifiedType& returnType(Context* context,
                                const TypedFnSignature* sig,
                                const PoiScope* poiScope) {
  QUERY_BEGIN(returnType, context, sig, poiScope);

  const UntypedFnSignature* untyped = sig->untyped();

  QualifiedType result;

  bool computed = helpComputeReturnType(context, sig, poiScope, result);
  if (!computed) {
    const AstNode* ast = parsing::idToAst(context, untyped->id());
    const Function* fn = ast->toFunction();
    CHPL_ASSERT(fn);

    // resolve the function body
    // resolveFunction will arrange to call computeReturnType
    // and store the return type in the result.
    const ResolvedFunction* rFn = resolveFunction(context, sig, poiScope);
    result = rFn->returnType();
  }

  return QUERY_END(result);
}

static const TypedFnSignature* const&
inferOutFormalsQuery(Context* context,
                     const TypedFnSignature* sig,
                     const PoiScope* instantiationPoiScope) {
  QUERY_BEGIN(inferOutFormalsQuery, context, sig, instantiationPoiScope);

  const UntypedFnSignature* untyped = sig->untyped();

  std::vector<types::QualifiedType> formalTypes;

  // resolve the function body
  const ResolvedFunction* rFn = resolveFunction(context, sig,
                                                instantiationPoiScope);
  const ResolutionResultByPostorderID& rr = rFn->resolutionById();

  int numFormals = sig->numFormals();
  for (int i = 0; i < numFormals; i++) {
    const types::QualifiedType& ft = sig->formalType(i);
    if (ft.kind() == QualifiedType::OUT && ft.isGenericOrUnknown()) {
      formalTypes.push_back(rr.byAst(untyped->formalDecl(i)).type());
    } else {
      formalTypes.push_back(ft);
    }
  }

  const TypedFnSignature* result = nullptr;
  result = TypedFnSignature::getInferred(context,
                                         std::move(formalTypes),
                                         sig);

  return QUERY_END(result);
}

const TypedFnSignature* inferOutFormals(Context* context,
                                        const TypedFnSignature* sig,
                                        const PoiScope* instantiationPoiScope) {
  if (sig == nullptr) {
    return nullptr;
  }

  bool anyGenericOutFormals = false;
  int numFormals = sig->numFormals();
  for (int i = 0; i < numFormals; i++) {
    const types::QualifiedType& ft = sig->formalType(i);
    if (ft.kind() == QualifiedType::OUT && ft.isGenericOrUnknown()) {
      anyGenericOutFormals = true;
      break;
    }
  }

  // if there are no 'out' formals with generic type, just return 'sig'.
  // also just return 'sig' if the function needs instantiation;
  // in that case, we can't infer the 'out' formals by resolving the body.
  if (anyGenericOutFormals && !sig->needsInstantiation()) {
    return inferOutFormalsQuery(context, sig, instantiationPoiScope);
  } else {
    return sig;
  }
}

void computeReturnType(Resolver& resolver) {

  QualifiedType returnType;
  bool computed = helpComputeReturnType(resolver.context,
                                        resolver.typedSignature,
                                        resolver.poiScope,
                                        returnType);
  if (computed) {
    resolver.returnType = returnType;
  } else if (auto fn = resolver.symbol->toFunction()) {
    const Type* declaredReturnType = nullptr;
    if (auto retTypeExpr = fn->returnType()) {
      auto qt = resolver.byPostorder.byAst(retTypeExpr).type();
      declaredReturnType = qt.type();

      if (declaredReturnType && declaredReturnType->isUnknownType()) {
        declaredReturnType = nullptr;
      }
    }

    // infer the return type
    auto v = ReturnTypeInferrer(resolver.context, fn, declaredReturnType);
    v.process(fn->body(), resolver.byPostorder);
    resolver.returnType = v.returnedType();
  }
}


} // end namespace resolution
} // end namespace chpl
