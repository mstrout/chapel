#include "astutil.h"
#include "expr.h"
#include "passes.h"
#include "stmt.h"
#include "symbol.h"
#include "symscope.h"

static bool
refNecessary(SymExpr* se) {
  if (se->var->defs.n > 1)
    return true;
  forv_Vec(SymExpr, use, se->var->uses) {
    if (CallExpr* call = toCallExpr(use->parentExpr)) {
      if (call->isResolved()) {
        ArgSymbol* formal = actual_to_formal(use);
        if (formal->defPoint->getFunction()->_this == formal)
          return true;
        if (formal->intent == INTENT_INOUT || formal->intent == INTENT_OUT)
          return true;
      } else if (call->isPrimitive(PRIMITIVE_MOVE)) {
        if (refNecessary(toSymExpr(call->get(1))))
          return true;
      } else if (call->isPrimitive(PRIMITIVE_SET_MEMBER)) {
        if (!call->get(2)->typeInfo()->refType)
          return true;
      } else if (call->isPrimitive(PRIMITIVE_RETURN)) {
        return true;
      }
    }
  }
  return false;
}


// removes references that are not necessary
void cullOverReferences() {
  Map<FnSymbol*,FnSymbol*> refMap; // reference fun to value fun

  //
  // make value functions from reference functions
  //
  forv_Vec(FnSymbol, fn, gFns) {
    if (fn->retTag == RET_VAR) {
      FnSymbol* copy = fn->copy();
      copy->retTag = RET_VALUE;
      fn->defPoint->insertBefore(new DefExpr(copy));
      VarSymbol* ret = new VarSymbol("ret", getValueType(fn->retType));
      INT_ASSERT(ret->type);
      CallExpr* call = toCallExpr(copy->body->body.last());
      if (!call || !call->isPrimitive(PRIMITIVE_RETURN))
        INT_FATAL(fn, "function is not normal");
      SymExpr* se = toSymExpr(call->get(1));
      if (!se)
        INT_FATAL(fn, "function is not normal");
      call->insertBefore(new DefExpr(ret));
      call->insertBefore(new CallExpr(PRIMITIVE_MOVE, ret,
                           new CallExpr(PRIMITIVE_GET_REF, se->var)));
      se->var = ret;
      copy->retType = ret->type;
      refMap.put(fn, copy);
    }
  }

  //
  // change "setter" to true or false depending on whether the symbol
  // appears in reference or value functions
  //
  Map<Symbol*,FnSymbol*> setterMap;
  forv_Vec(FnSymbol, fn, gFns) {
    if (fn->setter)
      setterMap.put(fn->setter->sym, fn);
  }
  forv_Vec(BaseAST, ast, gAsts) {
    if (SymExpr* se = toSymExpr(ast)) {
      if (FnSymbol* fn = setterMap.get(se->var)) {
        VarSymbol* tmp = new VarSymbol("_tmp", dtBool);
        tmp->isCompilerTemp = true;
        se->getStmtExpr()->insertBefore(new DefExpr(tmp));
        se->getStmtExpr()->insertBefore(new CallExpr(PRIMITIVE_MOVE, tmp, fn->retTag == RET_VAR ? gTrue : gFalse));
        se->var = tmp;
      }
    }
  }

  compute_sym_uses();

  forv_Vec(BaseAST, ast, gAsts) {
    if (CallExpr* call = toCallExpr(ast)) {
      //
      // change call of reference function to value function
      //
      if (FnSymbol* fn = call->isResolved()) {
        if (FnSymbol* copy = refMap.get(fn)) {
          if (CallExpr* move = toCallExpr(call->parentExpr)) {
            INT_ASSERT(move->isPrimitive(PRIMITIVE_MOVE));
            SymExpr* se = toSymExpr(move->get(1));
            INT_ASSERT(se);
            if (!refNecessary(se)) {
              VarSymbol* tmp = new VarSymbol("_tmp", copy->retType);
              move->insertBefore(new DefExpr(tmp));
              move->insertAfter(new CallExpr(PRIMITIVE_MOVE, se->var,
                                             new CallExpr(PRIMITIVE_SET_REF, tmp)));
              se->var = tmp;
              SymExpr* base = toSymExpr(call->baseExpr);
              base->var = copy;
            }
          } else {
            SymExpr* base = toSymExpr(call->baseExpr);
            base->var = copy;
          }
        }
      }
    }
  }

  //
  // Replace returned references to array or domain wrappers by array
  // or domain wrappers.  This handles the case where an array or
  // domain is returned in a var function and a new array or domain
  // wrapper is created.
  //
  Vec<FnSymbol*> derefSet; // reference functions that are changed to
                           // value functions

  forv_Vec(FnSymbol, fn, gFns) {
    if (fn->defPoint && fn->defPoint->parentSymbol && !fn->hasPragma("ref")) {
      if (Type* vt = getValueType(fn->retType)) {
        if (vt->symbol->hasPragma("array") ||
            vt->symbol->hasPragma("domain") ||
            vt->symbol->hasPragma("iterator class")) {
          fn->retType = vt;
          fn->retTag = RET_VALUE;
          Symbol* tmp = new VarSymbol("_tmp", vt);
          tmp->isCompilerTemp = true;
          CallExpr* ret = toCallExpr(fn->body->body.last());
          if (!ret || !ret->isPrimitive(PRIMITIVE_RETURN))
            INT_FATAL(fn, "function is not normal");
          ret->insertBefore(new DefExpr(tmp));
          ret->insertBefore(
            new CallExpr(PRIMITIVE_MOVE, tmp,
              new CallExpr(PRIMITIVE_GET_REF, ret->get(1)->remove())));
          ret->insertAtTail(tmp);
          derefSet.set_add(fn);
        }
      }
    }
  }
  forv_Vec(BaseAST, ast, gAsts) {
    if (CallExpr* call = toCallExpr(ast)) {
      if (FnSymbol* fn = call->isResolved()) {
        if (derefSet.set_in(fn)) {
          Symbol* tmp = new VarSymbol("_tmp", fn->retType);
          tmp->isCompilerTemp = true;
          Expr* stmt = call->getStmtExpr();
          stmt->insertBefore(new DefExpr(tmp));
          call->replace(new CallExpr(PRIMITIVE_SET_REF, tmp));
          stmt->insertBefore(new CallExpr(PRIMITIVE_MOVE, tmp, call));
        }
      }
    }
  }
}
