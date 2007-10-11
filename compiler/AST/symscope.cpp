#include "expr.h"
#include "stmt.h"
#include "runtime.h"
#include "stringutil.h"
#include "symscope.h"
#include "files.h"


SymScope::SymScope(BaseAST* iastParent, SymScope* iparent) :
  astParent(iastParent),
  parent(iparent)
{ }


SymScope::~SymScope() {
  Vec<const char*> keys;
  visibleFunctions.get_keys(keys);
  forv_Vec(const char, key, keys) {
    delete visibleFunctions.get(key);
  }
}


void SymScope::define(Symbol* sym) {
  if (FnSymbol* fn = toFnSymbol(sym)) {
    if (fn->global)
      theProgram->block->blkScope->addVisibleFunction(fn);
    else
      addVisibleFunction(fn);
  }
  Symbol* tmp = table.get(sym->name);
  if (tmp) {
    sym->overloadNext = tmp->overloadNext;
    sym->overloadPrev = tmp;
    if (tmp->overloadNext)
      tmp->overloadNext->overloadPrev = sym;
    tmp->overloadNext = sym;
    sym->setParentScope(tmp->parentScope);
  } else {
    table.put(sym->name, sym);
    sym->overloadNext = NULL;
    sym->overloadPrev = NULL;
    sym->setParentScope(this);
  }
}


void SymScope::undefine(Symbol* sym) {
  if (FnSymbol* fn = toFnSymbol(sym)) {
    theProgram->block->blkScope->removeVisibleFunction(fn);
    removeVisibleFunction(fn);
  }
  Symbol* tmp = table.get(sym->name);
  if (tmp == sym) {
    tmp = sym->overloadNext;
    table.del(sym->name);
    if (tmp)
      table.put(sym->name, tmp);
  } else {
    if (!sym->overloadPrev)
      INT_FATAL(sym, "Symbol not found in scope from which deleted");
    if (sym->overloadPrev)
      sym->overloadPrev->overloadNext = sym->overloadNext;
    if (sym->overloadNext)
      sym->overloadNext->overloadPrev = sym->overloadPrev;
  }
  sym->overloadNext = NULL;
  sym->overloadPrev = NULL;
}


Symbol*
SymScope::lookupLocal(const char* name, Vec<SymScope*>* alreadyVisited, bool returnModules) {
  Symbol* sym;

  if (!alreadyVisited) {
    Vec<SymScope*> scopes;
    return lookupLocal(name, &scopes, returnModules);
  }

  if (alreadyVisited->set_in(this))
    return NULL;

  alreadyVisited->set_add(this);

  sym = table.get(name);

  if (sym && (!toModuleSymbol(sym) || returnModules))
    return sym;

  if (astParent && astParent->getModule()->block == astParent) {
    ModuleSymbol* mod = astParent->getModule();
    sym = mod->initFn->body->blkScope->lookupLocal(name, alreadyVisited, returnModules);
    if (sym && (!toModuleSymbol(sym) || returnModules))
      return sym;
  }

  Vec<ModuleSymbol*>* modUses = getModuleUses();
  if (modUses) {
    forv_Vec(ModuleSymbol, module, *modUses) {
      sym = module->block->blkScope->lookup(name, alreadyVisited, returnModules);
      if (sym && (!toModuleSymbol(sym) || returnModules))
        return sym;
    }
  }

  return NULL;
}


Symbol*
SymScope::lookup(const char* name, Vec<SymScope*>* alreadyVisited, bool returnModules) {
  if (!alreadyVisited) {
    Vec<SymScope*> scopes;
    return lookup(name, &scopes, returnModules);
  }

  Symbol* sym = lookupLocal(name, alreadyVisited, returnModules);
  if (sym && (!toModuleSymbol(sym) || returnModules))
    return sym;
  if (FnSymbol* fn = toFnSymbol(astParent)) {
    if (fn->_this) {
      ClassType* ct = toClassType(fn->_this->type);
      if (ct) {
        Symbol* sym = ct->structScope->lookupLocal(name, alreadyVisited, returnModules);
        if (sym && (!toModuleSymbol(sym) || returnModules))
          return sym;
        Type* outerType = ct->symbol->defPoint->parentSymbol->type;
        if (ClassType* ot = toClassType(outerType)) {
          // Nested class.  Look at the scope of the outer class
          Symbol* sym = ot->structScope->lookup(name, alreadyVisited, returnModules);
          if (sym && (!toModuleSymbol(sym) || returnModules))
            return sym;
        }
      }
    }
  }
  if (parent)
    return parent->lookup(name, alreadyVisited, returnModules);
  return NULL;
}


void SymScope::addModuleUse(ModuleSymbol* mod) {
  Vec<ModuleSymbol*>* modUses = getModuleUses();
  if (!modUses)
    INT_FATAL(astParent, "Bad call to addModuleUse");
  modUses->add(mod);
}


Vec<ModuleSymbol*>* SymScope::getModuleUses() {
  if (BlockStmt* block = toBlockStmt(astParent))
    return &block->modUses;
  return NULL;
}


void SymScope::print() {
  print(false, 0);
}


void SymScope::print(bool number, int indent) {
  Vec<Symbol*> symbols;
  table.get_values(symbols);
  if (!symbols.n && (!astParent || !getModuleUses()->n))
    return;
  for (int i = 0; i < indent; i++)
    printf(" ");
  printf("=================================================================\n");
  for (int i = 0; i < indent; i++)
    printf(" ");
  if (astParent) {
    if (number)
      printf("%d", astParent->id);
    printf(" %s", astTagName[astParent->astTag]);
  }
  if (Symbol* sym = toSymbol(astParent))
    printf(" %s", sym->name);
  printf("\n");
  for (int i = 0; i < indent; i++)
    printf(" ");
  printf("-----------------------------------------------------------------\n");
  if (astParent) {
    forv_Vec(ModuleSymbol, mod, *getModuleUses()) {
      if (mod) {
        for (int i = 0; i < indent; i++)
          printf(" ");
        printf("use %s", mod->name);
        if (number)
          printf("[%d]", mod->id);
        printf("\n");
      }
    }
  }
  forv_Vec(Symbol, sym, symbols) {
    if (sym) {
      for (int i = 0; i < indent; i++)
        printf(" ");
      printf("%s (", sym->name);
      for (Symbol* tmp = sym; tmp; tmp = tmp->overloadNext) {
        printf("%s", tmp->cname);
        if (number)
          printf("[%d]", tmp->id);
        if (tmp->overloadNext)
          printf(", ");
      }
      printf(")\n");
    }
  }
  for (int i = 0; i < indent; i++)
    printf(" ");
  printf("=================================================================\n");
}


void SymScope::codegen(FILE* outfile) {
  Vec<Symbol*> symbols;
  table.get_values(symbols);
  forv_Vec(Symbol, sym, symbols) {
    for (Symbol* tmp = sym; tmp; tmp = tmp->overloadNext)
      if (!toTypeSymbol(tmp))
        tmp->codegenDef(outfile);
  }
}


static int compareLineno(const void* v1, const void* v2) {
  FnSymbol* fn1 = *(FnSymbol**)v1;
  FnSymbol* fn2 = *(FnSymbol**)v2;
  if (fn1->lineno > fn2->lineno)
    return 1;
  else if (fn1->lineno < fn2->lineno)
    return -1;
  else
    return 0;
}


void SymScope::codegenFunctions(FILE* outfile) {
  Vec<FnSymbol*> fns;
  Vec<Symbol*> symbols;
  table.get_values(symbols);
  forv_Vec(Symbol, sym, symbols) {
    for (Symbol* tmp = sym; tmp; tmp = tmp->overloadNext) {
      if (FnSymbol* fn = toFnSymbol(tmp)) {
        if (!fn->isExtern)
          fns.add(fn);
      }
    }
  }
  qsort(fns.v, fns.n, sizeof(fns.v[0]), compareLineno);
  forv_Vec(FnSymbol, fn, fns) {
    fn->codegenDef(outfile);
  }
}


void SymScope::addVisibleFunction(FnSymbol* fn) {
  if (!fn->visible)
    return;
  Vec<FnSymbol*>* fs = visibleFunctions.get(fn->name);
  if (!fs) fs = new Vec<FnSymbol*>;
  fs->add(fn);
  visibleFunctions.put(fn->name, fs);
}


void SymScope::removeVisibleFunction(FnSymbol* fn) {
  if (!fn->visible)
    return;
  Vec<FnSymbol*>* fs = visibleFunctions.get(fn->name);
  if (!fs) return;
  for (int i = 0; i < fs->n; i++) {
    if (fs->v[i] == fn) {
      fs->v[i] = NULL;
    }
  }
}


void SymScope::getVisibleFunctions(Vec<FnSymbol*>* allVisibleFunctions,
                                   const char* name,
                                   bool recursed) {

  // to avoid infinite loop because of cyclic module uses
  static Vec<SymScope*> visited;
  if (!recursed)
    visited.clear();
  if (visited.set_in(this))
    return;
  visited.set_add(this);

  Vec<FnSymbol*>* fs = visibleFunctions.get(name);
  if (fs)
    allVisibleFunctions->append(*fs);
  Vec<ModuleSymbol*>* modUses = getModuleUses();
  if (modUses) {
    forv_Vec(ModuleSymbol, module, *modUses) {
      module->block->blkScope->getVisibleFunctions(allVisibleFunctions, name, true);
    }
  }
  if (astParent) {
    if (FnSymbol* fn = toFnSymbol(astParent)) {
      if (fn->visiblePoint && fn->visiblePoint->parentScope)
        fn->visiblePoint->parentScope->getVisibleFunctions(allVisibleFunctions, name, true);
    }
    if (astParent->getModule()->block == astParent) {
      ModuleSymbol* mod = astParent->getModule();
      mod->initFn->body->blkScope->getVisibleFunctions(allVisibleFunctions, name, true);
    }
  }
  if (parent)
    parent->getVisibleFunctions(allVisibleFunctions, name, true);
}
