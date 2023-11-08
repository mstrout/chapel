/*
 * Copyright 2021-2023 Hewlett Packard Enterprise Development LP
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

#include "chpl/resolution/disambiguation.h"

#include "chpl/parsing/parsing-queries.h"
#include "chpl/framework/query-impl.h"
#include "chpl/resolution/can-pass.h"
#include "chpl/resolution/resolution-queries.h"
#include "chpl/resolution/scope-queries.h"
#include "chpl/types/all-types.h"
#include "chpl/uast/Function.h"

namespace chpl {
namespace resolution {


using namespace uast;
using namespace types;

struct DisambiguationCandidate {
  const TypedFnSignature* fn = nullptr;
  QualifiedType forwardingTo; // actual passed to receiver when forwarding
  FormalActualMap formalActualMap;
  int idx = 0;
  bool anyPromotes = false;
  bool nImplicitConversionsComputed = false;
  bool anyNegParamToUnsigned = false;
  int nImplicitConversions = 0;
  int nParamNarrowingImplicitConversions = 0;
  // What is the visibility distance? This is -1 if it has not been computed.
  int visibilityDistance = -1;

  DisambiguationCandidate(const TypedFnSignature* fn,
                          QualifiedType forwardingTo,
                          const CallInfo& call,
                          int idx)
    : fn(fn), forwardingTo(forwardingTo), formalActualMap(fn, call), idx(idx),
      anyPromotes(false), nImplicitConversionsComputed(false),
      anyNegParamToUnsigned(false), nImplicitConversions(0),
      nParamNarrowingImplicitConversions(0), visibilityDistance(-1)
  {
  }

  MostSpecificCandidate toMostSpecificCandidate(Context* context) const {
    return MostSpecificCandidate::fromTypedFnSignature(context, fn, formalActualMap);
  }
};

struct DisambiguationContext {
  Context* context = nullptr;
  const CallInfo* call = nullptr;
  const Scope* callInScope = nullptr;
  const PoiScope* callInPoiScope = nullptr;
  bool explain = false;
  bool isMethodCall = false;
  bool useOldVisibility = false;
  DisambiguationContext(Context* context,
                        const CallInfo* call,
                        const Scope* callInScope,
                        const PoiScope* callInPoiScope,
                        bool explain)
    : context(context), call(call),
      callInScope(callInScope), callInPoiScope(callInPoiScope),
      explain(explain)
  {
    isMethodCall = call->isMethodCall();

    // this is a workaround -- a better solution would be preferred
    if (parsing::idIsInInternalModule(context, callInScope->id())) {
      useOldVisibility = true;
    }

    // this is a workaround -- a better solution would be preferred.
    // this function seems to be created in a way that has problems with
    // the visibility logic in disambiguation.
    if (call->name() == "_getIterator") {
      useOldVisibility = true;
    }
  }
};

struct DisambiguationState {
  bool fn1NonParamArgsPreferred = false;
  bool fn2NonParamArgsPreferred = false;

  bool fn1ParamArgsPreferred = false;
  bool fn2ParamArgsPreferred = false;

  // TODO: Remove all these
  bool  fn1MoreSpecific = false;
  bool  fn2MoreSpecific = false;

  bool  fn1Promotes = false;
  bool  fn2Promotes = false;

  bool fn1WeakPreferred = false;
  bool fn2WeakPreferred = false;

  bool fn1WeakerPreferred = false;
  bool fn2WeakerPreferred = false;

  bool fn1WeakestPreferred = false;
  bool fn2WeakestPreferred = false;
};

using CandidatesVec = std::vector<const DisambiguationCandidate*>;

enum MoreVisibleResult {
  FOUND_F1_FIRST,
  FOUND_F2_FIRST,
  FOUND_BOTH,
  FOUND_NEITHER
};

#ifdef ENABLE_TRACING_OF_DISAMBIGUATION

#define EXPLAIN(...) \
        if (dctx.explain) fprintf(stderr, __VA_ARGS__)

#define EXPLAIN_DUMP(thing) \
        if (dctx.explain) { \
          (thing)->dump(StringifyKind::CHPL_SYNTAX); \
          fprintf(stderr, "\n"); \
        }

#else

#define EXPLAIN(...)
#define EXPLAIN_DUMP(thing)

#endif

static const DisambiguationCandidate*
findMostSpecificIgnoringReturn(const DisambiguationContext& dctx,
                               const CandidatesVec& candidates,
                               bool ignoreWhere,
                               CandidatesVec& ambiguousBest);

static int compareSpecificity(const DisambiguationContext& dctx,
                              const DisambiguationCandidate& candidate1,
                              const DisambiguationCandidate& candidate2,
                              int i,
                              int j,
                              bool forGenericInit);

static int compareSpecificity(const DisambiguationContext& dctx,
                              const DisambiguationCandidate& candidate1,
                              const DisambiguationCandidate& candidate2,
                              bool ignoreWhere);

static MoreVisibleResult moreVisible(const DisambiguationContext& dctx,
                                     const DisambiguationCandidate& candidate1,
                                     const DisambiguationCandidate& candidate2);

static int testArgMapping(const DisambiguationContext& dctx,
                          const DisambiguationCandidate& candidate1,
                          const DisambiguationCandidate& candidate2,
                          int actualIdx,
                          DisambiguationState& ds,
                          std::string& reason);

static void testArgMapping(const DisambiguationContext& dctx,
                           const DisambiguationCandidate& candidate1,
                           const DisambiguationCandidate& candidate2,
                           int actualIdx,
                           DisambiguationState& ds);

static void testArgMapHelper(const DisambiguationContext& dctx,
                             const FormalActual& fa,
                             const QualifiedType& forwardingTo,
                             bool* formalPromotes, bool* formalNarrows,
                             DisambiguationState& ds,
                             int fnNum);

static int testOpArgMapping(const DisambiguationContext& dctx,
                            const DisambiguationCandidate& candidate1,
                            const DisambiguationCandidate& candidate2,
                            int actualIdx,
                            DisambiguationState& ds,
                            std::string& reason);

static bool isFormalInstantiatedAny(const DisambiguationCandidate& candidate,
                                    const FormalActual* fa);

static bool isFormalPartiallyGeneric(const DisambiguationCandidate& candidate,
                                     const FormalActual* fa);

static bool prefersConvToOtherNumeric(const DisambiguationContext& dctx,
                                      QualifiedType actualType,
                                      QualifiedType f1Type,
                                      QualifiedType f2Type);

static QualifiedType computeActualScalarType(Context* context,
                                             QualifiedType actualType);

static bool isNumericParamDefaultType(QualifiedType type);

static bool moreSpecificCanDispatch(const DisambiguationContext& dctx,
                                    QualifiedType actualType,
                                    QualifiedType formalType);

static MostSpecificCandidates
computeMostSpecificCandidatesWithVecs(Context* context,
                                      const DisambiguationContext& dctx,
                                      const CandidatesVec& vec);

static void discardWorseVisibility(const DisambiguationContext& dctx,
                                   const CandidatesVec& candidates,
                                   std::vector<bool>& discarded);

static void discardWorseArgs(const DisambiguationContext& dctx,
                             const CandidatesVec& candidates,
                             std::vector<bool>& discarded);

static void discardWorsePromoting(const DisambiguationContext& dctx,
                                  const CandidatesVec& candidates,
                                  std::vector<bool>&  discarded);

static void discardWorseWhereClauses(const DisambiguationContext& dctx,
                                     const CandidatesVec& candidates,
                                     std::vector<bool>& discarded);

static void discardWorseConversions(const DisambiguationContext& dctx,
                                    const CandidatesVec& candidates,
                                    std::vector<bool>& discarded);

static void disambiguateDiscarding(const DisambiguationContext&   dctx,
                                   const CandidatesVec& candidates,
                                   bool ignoreWhere,
                                   std::vector<bool>&   discarded);

static int prefersNumericCoercion(const DisambiguationContext& dctx,
                                  QualifiedType f1Qt,
                                  QualifiedType f2Qt,
                                  QualifiedType actualQt,
                                  std::string &reason);

// count the number of candidates with each return intent
static void countByReturnIntent(const DisambiguationContext& dctx,
                                const CandidatesVec& vec,
                                int& nRef,
                                int& nConstRef,
                                int& nValue,
                                int& nOther) {
  for (auto c : vec) {
    auto fn = c->fn;
    auto returnIntent = parsing::idToFnReturnIntent(dctx.context, fn->id());

    switch (returnIntent) {
      case Function::DEFAULT_RETURN_INTENT:
      case Function::OUT:
      case Function::CONST:
        nValue++;
        break;
      case Function::CONST_REF:
        nConstRef++;
        break;
      case Function::REF:
        nRef++;
        break;
      case Function::PARAM:
      case Function::TYPE:
        nOther++;
        break;
    }
  }
}

// if there is <= 1 most specific candidate with each intent,
// return it as a MostSpecificCandidates
static MostSpecificCandidates
gatherByReturnIntent(Context* context,
                     const DisambiguationContext& dctx,
                     const CandidatesVec& vec) {
  MostSpecificCandidates ret;

  for (auto c : vec) {
    auto fn = c->fn;
    auto returnIntent = parsing::idToFnReturnIntent(dctx.context, fn->id());

    switch (returnIntent) {
      case Function::DEFAULT_RETURN_INTENT:
      case Function::OUT:
      case Function::CONST:
        CHPL_ASSERT(!ret.bestValue());
        ret.setBestValue(c->toMostSpecificCandidate(context));
        break;
      case Function::CONST_REF:
        CHPL_ASSERT(!ret.bestConstRef());
        ret.setBestConstRef(c->toMostSpecificCandidate(context));
        break;
      case Function::REF:
        CHPL_ASSERT(!ret.bestRef());
        ret.setBestRef(c->toMostSpecificCandidate(context));
        break;
      case Function::PARAM:
      case Function::TYPE:
        CHPL_ASSERT(false && "should not be reachable");
        break;
    }
  }

  return ret;
}

// Gather the most specific candidates with each return intent into vectors
// by return intent
static void gatherVecsByReturnIntent(const DisambiguationContext& dctx,
                                     const CandidatesVec& vec,
                                     CandidatesVec& refCandidates,
                                     CandidatesVec& constRefCandidates,
                                     CandidatesVec& valueCandidates) {
  for (auto c : vec) {
    auto fn = c->fn;
    auto returnIntent = parsing::idToFnReturnIntent(dctx.context, fn->id());

    switch (returnIntent) {
      case Function::DEFAULT_RETURN_INTENT:
      case Function::OUT:
      case Function::CONST:
        valueCandidates.push_back(c);
        break;
      case Function::CONST_REF:
        constRefCandidates.push_back(c);
        break;
      case Function::REF:
        refCandidates.push_back(c);
        break;
      case Function::PARAM:
      case Function::TYPE:
        break;
    }
  }
}

static MostSpecificCandidates
computeMostSpecificCandidates(Context* context,
                              const DisambiguationContext& dctx,
                              const CandidatesVec& candidates) {

  CandidatesVec ambiguousBest;

  // The common case is that there is no ambiguity because the
  // return intent overload feature is not used.
  auto best = findMostSpecificIgnoringReturn(dctx, candidates,
                                             /* ignoreWhere */ true,
                                             ambiguousBest);

  if (best != nullptr) {
    return MostSpecificCandidates::getOnly(best->toMostSpecificCandidate(context));
  }

  if (ambiguousBest.size() == 0) {
    // nothing to do, return no candidates
    return MostSpecificCandidates::getEmpty();
  }

  // Now, if there was ambiguity, try again while considering
  // separately each category of return intent.
  //
  // If there is only one most specific function in each category,
  // that is what we need to return.
  int nRef = 0;
  int nConstRef = 0;
  int nValue = 0;
  int nOther = 0;

  // Count number of candidates in each category.
  countByReturnIntent(dctx, ambiguousBest, nRef, nConstRef, nValue, nOther);

  if (nOther > 0) {
    // If there are *any* type/param candidates, we need to cause ambiguity
    // if they are not selected... including consideration of where clauses.
    ambiguousBest.clear();
    auto best = findMostSpecificIgnoringReturn(dctx, candidates,
                                               /* ignoreWhere */ false,
                                               ambiguousBest);

    if (ambiguousBest.size() > 1)
      return MostSpecificCandidates::getAmbiguous();

    return MostSpecificCandidates::getOnly(best->toMostSpecificCandidate(context));
  }

  if (nRef <= 1 && nConstRef <= 1 && nValue <= 1) {
    return gatherByReturnIntent(context, dctx, ambiguousBest);
  }

  // Otherwise, nRef > 1 || nConstRef > 1 || nValue > 1.

  // handle the more complex case where there is > 1 candidate
  // with a particular return intent by disambiguating each group
  // individually.
  return computeMostSpecificCandidatesWithVecs(context, dctx, ambiguousBest);
}

static MostSpecificCandidates
computeMostSpecificCandidatesWithVecs(Context* context,
                                      const DisambiguationContext& dctx,
                                      const CandidatesVec& vec) {
  CandidatesVec refCandidates;
  CandidatesVec constRefCandidates;
  CandidatesVec valueCandidates;
  CandidatesVec ambiguousBest;

  // Split candidates into ref, const ref, and value candidates
  gatherVecsByReturnIntent(dctx, vec,
                           refCandidates,
                           constRefCandidates,
                           valueCandidates);

  // Disambiguate each group and update the counts
  int nRef = 0;
  int nConstRef = 0;
  int nValue = 0;

  bool ignoreWhere = false;

  ambiguousBest.clear();
  auto bestRef = findMostSpecificIgnoringReturn(dctx, refCandidates,
                                                ignoreWhere, ambiguousBest);
  if (bestRef != nullptr) {
    nRef = 1;
  } else {
    nRef = ambiguousBest.size();
  }

  ambiguousBest.clear();
  auto bestCRef = findMostSpecificIgnoringReturn(dctx, constRefCandidates,
                                                     ignoreWhere, ambiguousBest);
  if (bestCRef != nullptr) {
    nConstRef = 1;
  } else {
    nConstRef = ambiguousBest.size();
  }

  ambiguousBest.clear();
  auto bestValue = findMostSpecificIgnoringReturn(dctx, valueCandidates,
                                                  ignoreWhere, ambiguousBest);
  if (bestValue != nullptr) {
    nValue = 1;
  } else {
    nValue = ambiguousBest.size();
  }

  // if there is > 1 match in any category, fail to match due to ambiguity
  if (nRef > 1 || nConstRef > 1 || nValue > 1) {
    return MostSpecificCandidates::getAmbiguous();
  }

  // otherwise, there is 1 or fewer match in each category,
  // so there is no ambiguity.
  MostSpecificCandidates ret;
  if (bestRef != nullptr)
    ret.setBestRef(bestRef->toMostSpecificCandidate(context));
  if (bestCRef != nullptr)
    ret.setBestConstRef(bestCRef->toMostSpecificCandidate(context));
  if (bestValue != nullptr)
    ret.setBestValue(bestValue->toMostSpecificCandidate(context));

  return ret;
}

// handle the more complex case where there is > 1 candidate
// with a particular return intent by disambiguating each group
// individually.
static MostSpecificCandidates
computeMostSpecificCandidatesWithVecs(Context* context,
                                      const DisambiguationContext& dctx,
                                      const CandidatesVec& vec);


static const MostSpecificCandidates&
findMostSpecificCandidatesQuery(Context* context,
                                std::vector<const TypedFnSignature*> lst,
                                std::vector<QualifiedType> forwardingInfo,
                                CallInfo call,
                                const Scope* callInScope,
                                const PoiScope* callInPoiScope) {
  QUERY_BEGIN(findMostSpecificCandidatesQuery, context,
              lst, forwardingInfo, call, callInScope, callInPoiScope);

  // Construct the DisambiguationContext
  bool explain = true;
  DisambiguationContext dctx(context, &call,
                             callInScope, callInPoiScope,
                             explain);

  // Compute all of the FormalActualMaps now
  std::vector<const DisambiguationCandidate*> candidates;
  {
    int n = lst.size();
    for (int i = 0; i < n; i++) {
      QualifiedType forwardingTo;
      if (!forwardingInfo.empty()) {
        forwardingTo = forwardingInfo[i];
      }
      candidates.push_back(
          new DisambiguationCandidate(lst[i], forwardingTo, call, i));
    }
  }

  // If index i is set we have ruled out that function
  std::vector<bool> discarded(candidates.size(), false);
  disambiguateDiscarding(dctx, candidates, true /*ignoreWhere*/, discarded);

  MostSpecificCandidates result =
    computeMostSpecificCandidates(context, dctx, candidates);

  // Delete all of the FormalActualMaps
  for (auto elt : candidates) {
    delete elt;
  }

  return QUERY_END(result);
}

// entry point for disambiguation
MostSpecificCandidates
findMostSpecificCandidates(Context* context,
                           const std::vector<const TypedFnSignature*>& lst,
                           const std::vector<QualifiedType>& forwardingInfo,
                           const CallInfo& call,
                           const Scope* callInScope,
                           const PoiScope* callInPoiScope) {
  if (lst.size() == 0) {
    // nothing to do, return no candidates
    return MostSpecificCandidates::getEmpty();
  }

  if (lst.size() == 1) {
    // If there is just one candidate, return it
    return MostSpecificCandidates::getOnly(MostSpecificCandidate::fromTypedFnSignature(context, lst[0], call));
  }

  // if we get here, > 1 candidates
  // run the query to handle the more complex case
  // TODO: is it worth storing this in a query? Or should
  // we recompute it each time?
  return findMostSpecificCandidatesQuery(context, lst, forwardingInfo,
                                         call,
                                         callInScope, callInPoiScope);
}

/*
  Find the most specific candidate and returns it, ignoring
  return intents.

  If there is not a single most specific candidate, and ambiguousBest is not
  nullptr, appends the possibly-best candidates to ambiguousBest.

  Does not consider return intent overloading.
  */
static const DisambiguationCandidate*
findMostSpecificIgnoringReturn(const DisambiguationContext& dctx,
                               const CandidatesVec& candidates,
                               bool ignoreWhere,
                               CandidatesVec& ambiguousBest) {
  int n = candidates.size();

  if (n == 0) {
    // nothing to do
    return nullptr;
  }

  if (n == 1) {
    // the only match is the best match
    return candidates[0];
  }

  // If index i is set then we can skip testing function F_i because
  // we already know it can not be the best match.
  std::vector<bool> notBest(n, false);

  for (int i = 0; i < n; i++) {
    EXPLAIN("##########################\n");
    EXPLAIN("# Considering function %d #\n", i);
    EXPLAIN("##########################\n\n");

    const DisambiguationCandidate* candidate1 = candidates[i];
    bool singleMostSpecific = true;

    EXPLAIN_DUMP(candidate1->fn);

    if (notBest[i]) {
      EXPLAIN("Already known to not be best match.  Skipping.\n\n");
      continue;
    }

    for (int j = 0; j < n; j++) {
      if (i == j) {
        continue;
      }

      EXPLAIN("Comparing to function %d\n", j);
      EXPLAIN("-----------------------\n");

      const DisambiguationCandidate* candidate2 = candidates[j];

      EXPLAIN_DUMP(candidate2->fn);

      int cmp = compareSpecificity(dctx, *candidate1, *candidate2, ignoreWhere);

      if (cmp < 0) {
        EXPLAIN("X: Fn %d is a better match than Fn %d\n\n\n", i, j);
        notBest[j] = true;

      } else if (cmp > 0) {
        EXPLAIN("X: Fn %d is a worse match than Fn %d\n\n\n", i, j);
        notBest[i] = true;
        singleMostSpecific = false;
        break;
      } else {
        EXPLAIN("X: Fn %d is a as good a match as Fn %d\n\n\n", i, j);
        singleMostSpecific = false;
        if (notBest[j]) {
          // Inherit the notBest status of what we are comparing against
          //
          // If this candidate is equally as good as something that wasn't
          // the best, then it is also not the best (or else there is something
          // terribly wrong with our compareSpecificity function).
          notBest[i] = true;
        }
        break;
      }
    }

    if (singleMostSpecific) {
      EXPLAIN("Y: Fn %d is the best match.\n\n\n", i);
      return candidates[i];

    } else {
      EXPLAIN("Y: Fn %d is NOT the best match.\n\n\n", i);
    }
  }

  EXPLAIN("Z: No non-ambiguous best match.\n\n");

  for (int i = 0; i < n; i++) {
    if (notBest[i] == false) {
      ambiguousBest.push_back(candidates[i]);
    }
  }

  return nullptr;
}

/**

  Determines if fn1 is a better match than fn2.

  This function implements the function comparison component of the
  disambiguation procedure as detailed in section 13.13 of the Chapel
  language specification.

  \param candidate1 The function on the left-hand side of the comparison.
  \param candidate2 The function on the right-hand side of the comparison.


  \return -1 if the two functions are incomparable
  \return 0 if the two functions are equally specific
  \return 1 if fn1 is a more specific function than f2
  \return 2 if fn2 is a more specific function than f1
 */
static int compareSpecificity(const DisambiguationContext& dctx,
                              const DisambiguationCandidate& candidate1,
                              const DisambiguationCandidate& candidate2,
                              int i,
                              int j,
                              bool forGenericInit) {

  bool prefer1 = false;
  bool prefer2 = false;
  int n = dctx.call->numActuals();
  int nArgsIncomparable = 0;
  std::string reason;
  DisambiguationState ds;

  // Initializer work-around: Skip _mt/_this for generic initializers
  int start = (forGenericInit == false) ? 0 : 2;

  for (int k = start; k < n; k++) {

    EXPLAIN("\nLooking at argument %d\n", k);
    const FormalActual* fa1 = candidate1.formalActualMap.byActualIdx(k);
    const FormalActual* fa2 = candidate2.formalActualMap.byActualIdx(k);

    if (fa1 == nullptr || fa2 == nullptr) {
      if (candidate1.fn->untyped()->kind()==Function::Kind::OPERATOR &&
          candidate2.fn->untyped()->kind()==Function::Kind::OPERATOR) {
        EXPLAIN("\nSkipping argument %d because could be in an operator call\n", k);
        continue;
      } else {
        // One of the two candidate functions was not an operator, but one
        // was so we need to do something special here.
        int p = testOpArgMapping(dctx, candidate1, candidate2, k, ds, reason);
        std::string reason = "operator method vs function";
        if (p == 1) {
          ds.fn1NonParamArgsPreferred = true;
          EXPLAIN("%s: Fn %d is non-param preferred\n", reason, i);
        } else if (p == 2) {
          ds.fn2NonParamArgsPreferred = true;
            EXPLAIN("%s: Fn %d is non-param preferred\n", reason, j);
        }
        continue;
      }
    }

    bool actualParam = fa1->actualType().isParam();


    int p = testArgMapping(dctx, candidate1, candidate2, k, ds, reason);
    if (p == -1) {
      nArgsIncomparable++;
    }

    if (actualParam) {
      if (p == 1) {
        ds.fn1ParamArgsPreferred = true;
        EXPLAIN("%s: Fn %d is param preferred\n", reason, i);
      } else if (p == 2) {
        ds.fn2ParamArgsPreferred = true;
        EXPLAIN("%s: Fn %d is param preferred\n", reason, j);
      }
    } else {
      if (p == 1) {
        ds.fn1NonParamArgsPreferred = true;
        EXPLAIN("%s: Fn %d is non-param preferred\n", reason, i);
      } else if (p == 2) {
        ds.fn2NonParamArgsPreferred = true;
        EXPLAIN("%s: Fn %d is non-param preferred\n", reason, j);
      }
    }
  }
  if (ds.fn1NonParamArgsPreferred != ds.fn2NonParamArgsPreferred) {
    EXPLAIN("\nP: only one function has preferred non-param args\n");

    prefer1 = ds.fn1NonParamArgsPreferred;
    prefer2 = ds.fn2NonParamArgsPreferred;

  } else if (ds.fn1ParamArgsPreferred != ds.fn2ParamArgsPreferred) {
    EXPLAIN("\nP1: only one function has preferred param args\n");

    prefer1 = ds.fn1ParamArgsPreferred;
    prefer2 = ds.fn2ParamArgsPreferred;

  }

  if (prefer1) {
    EXPLAIN("\nW: Fn %d is more specific than Fn %d\n", i, j);
    return 1;

  } else if (prefer2) {
    EXPLAIN("\nW: Fn %d is less specific than Fn %d\n", i, j);
    return 2;

  } else {
    if (nArgsIncomparable > 0 ||
        (ds.fn1NonParamArgsPreferred && ds.fn2NonParamArgsPreferred) ||
        (ds.fn1ParamArgsPreferred && ds.fn2ParamArgsPreferred)) {
      EXPLAIN("\nW: Fn %d and Fn %d are incomparable\n", i, j);
      return -1;
    }

    EXPLAIN("\nW: Fn %d and Fn %d are equally specific\n", i, j);
    return 0;
  }
}

/**

  Determines if fn1 is a better match than fn2.

  This function implements the function comparison component of the
  disambiguation procedure as detailed in section 13.13 of the Chapel
  language specification.

  \param candidate1 The function on the left-hand side of the comparison.
  \param candidate2 The function on the right-hand side of the comparison.
  \param ignoreWhere Set to `true` to ignore `where` clauses when
                     deciding if one match is better than another.
                     This is important for resolving return intent
                     overloads.

  \return -1 if fn1 is a more specific function than f2
  \return 0 if fn1 and fn2 are equally specific
  \return 1 if fn2 is a more specific function than f1
 */
static int compareSpecificity(const DisambiguationContext& dctx,
                              const DisambiguationCandidate& candidate1,
                              const DisambiguationCandidate& candidate2,
                              bool ignoreWhere) {

  bool prefer1 = false;
  bool prefer2 = false;
  int n = dctx.call->numActuals();
  DisambiguationState ds;

  for (int k = 0; k < n; k++) {
    testArgMapping(dctx, candidate1, candidate2, k, ds);
  }

  if (ds.fn1Promotes != ds.fn2Promotes) {
    EXPLAIN("\nP: only one of the functions requires argument promotion\n");

    // Prefer the version that did not promote
    prefer1 = !ds.fn1Promotes;
    prefer2 = !ds.fn2Promotes;

  } else if (ds.fn1MoreSpecific != ds.fn2MoreSpecific) {
    EXPLAIN("\nP1: only one more specific argument mapping\n");

    prefer1 = ds.fn1MoreSpecific;
    prefer2 = ds.fn2MoreSpecific;

  } else {
    // If the decision hasn't been made based on the argument mappings...
    auto moreVis = moreVisible(dctx, candidate1, candidate2);
    if (moreVis == MoreVisibleResult::FOUND_F1_FIRST) {
      EXPLAIN("\nQ: preferring more visible function\n");
      prefer1 = true;

    } else if (moreVis == MoreVisibleResult::FOUND_F2_FIRST) {
      EXPLAIN("\nR: preferring more visible function\n");
      prefer2 = true;

    } else if (ds.fn1WeakPreferred != ds.fn2WeakPreferred) {
      EXPLAIN("\nS: preferring based on weak preference\n");
      prefer1 = ds.fn1WeakPreferred;
      prefer2 = ds.fn2WeakPreferred;

    } else if (ds.fn1WeakerPreferred != ds.fn2WeakerPreferred) {
      EXPLAIN("\nS: preferring based on weaker preference\n");
      prefer1 = ds.fn1WeakerPreferred;
      prefer2 = ds.fn2WeakerPreferred;

    } else if (ds.fn1WeakestPreferred != ds.fn2WeakestPreferred) {
      EXPLAIN("\nS: preferring based on weakest preference\n");
      prefer1 = ds.fn1WeakestPreferred;
      prefer2 = ds.fn2WeakestPreferred;

      /* A note about weak-prefers. Why are there 3 levels?

         Something like 'param x:int(16) = 5' should be able to coerce to any
         integral type. Meanwhile, 'param y = 5' should also be able to coerce
         to any integral type. Now imagine we are resolving 'x+y'.  We
         want it to resolve to the 'int(16)' version because 'x' has a type
         specified, but 'y' is a default type. Before the 3 weak levels, this
         version was chosen simply because non-default-sized ints didn't allow
         param conversion.

       */
    } else if (!ignoreWhere) {
      ID id1 = candidate1.fn->id();
      ID id2 = candidate2.fn->id();
      bool fn1where = parsing::idIsFunctionWithWhere(dctx.context, id1);
      bool fn2where = parsing::idIsFunctionWithWhere(dctx.context, id2);

      if (fn1where != fn2where) {
        EXPLAIN("\nU: preferring function with where clause\n");

        prefer1 = fn1where;
        prefer2 = fn2where;
      }
    }
  }

  CHPL_ASSERT(!(prefer1 && prefer2));

  if (prefer1) {
    EXPLAIN("\nW: Fn %d is more specific than Fn %d\n",
            candidate1.idx, candidate2.idx);
    return -1;

  } else if (prefer2) {
    EXPLAIN("\nW: Fn %d is less specific than Fn %d\n",
            candidate1.idx, candidate2.idx);
    return 1;

  } else {
    // Neither is more specific
    EXPLAIN("\nW: Fn %d and Fn %d are equally specific\n",
            candidate1.idx, candidate2.idx);
    return 0;
  }
}

/*
 * Returns:
 *   0 if there is no preference between them
 *   1 if fn1 is preferred
 *   2 if fn2 is preferred
*/
static int testOpArgMapping(const DisambiguationContext& dctx,
                           const DisambiguationCandidate& candidate1,
                           const DisambiguationCandidate& candidate2,
                           int actualIdx,
                           DisambiguationState& ds,
                           std::string& reason) {
  // Validate our assumptions in this function - only operator functions should
  // return a NULL for the formal and they should only do so for method token
  // and "this" actuals.

  const FormalActual* fa1 = candidate1.formalActualMap.byActualIdx(actualIdx);
  const FormalActual* fa2 = candidate2.formalActualMap.byActualIdx(actualIdx);

  CHPL_ASSERT((candidate1.fn->untyped()->kind()==Function::Kind::OPERATOR) == (fa1 == nullptr));
  CHPL_ASSERT((candidate2.fn->untyped()->kind()==Function::Kind::OPERATOR) == (fa2 == nullptr));
  CHPL_ASSERT(fa1->actualType() == fa2->actualType());

  if (fa1 == nullptr) {
    CHPL_ASSERT(fa2 != nullptr);

    bool formal2Promotes = false;
    bool formal2Narrows = false;

    testArgMapHelper(dctx, *fa2, candidate2.forwardingTo,
                     &formal2Promotes, &formal2Narrows, ds, 2);
    return 2;

  } else {
    CHPL_ASSERT(fa2 == nullptr);

    bool formal1Promotes = false;
    bool formal1Narrows = false;

    testArgMapHelper(dctx, *fa1, candidate1.forwardingTo,
                     &formal1Promotes, &formal1Narrows, ds, 1);

    return 1;
  }

  return 0;

}


static MoreVisibleResult
checkVisibilityInVec(Context* context,
                     const std::vector<BorrowedIdsWithName>& vec,
                     ID fn1Id,
                     ID fn2Id) {
  bool found1 = false;
  bool found2 = false;
  for (const auto& borrowedIds : vec) {
    for (const auto& id : borrowedIds) {
      if (id == fn1Id) found1 = true;
      if (id == fn2Id) found2 = true;
    }
  }

  if (found1 || found2) {
    if (found1 && found2)
      return MoreVisibleResult::FOUND_BOTH;
    if (found1)
      return MoreVisibleResult::FOUND_F1_FIRST;
    if (found2)
      return MoreVisibleResult::FOUND_F2_FIRST;
  }

  return MoreVisibleResult::FOUND_NEITHER;
}

//
// helper routines for isMoreVisible (below);
//
static bool
isDefinedInBlock(Context* context, const Scope* scope,
                 const TypedFnSignature* fn) {
  LookupConfig onlyDecls = LOOKUP_DECLS | LOOKUP_METHODS;
  auto decls = lookupNameInScope(context, scope,
                                 /* receiver scopes */ {},
                                 fn->untyped()->name(), onlyDecls);
  for (const auto& borrowedIds : decls) {
    for (const auto& id : borrowedIds) {
      if (id == fn->id()) return true;
    }
  }
  return false;
}

static bool
isDefinedInUseImport(Context* context, const Scope* scope,
                     const TypedFnSignature* fn,
                     bool allowPrivateUseImp, bool forShadowScope) {
  LookupConfig importAndUse = LOOKUP_IMPORT_AND_USE | LOOKUP_METHODS;

  if (!forShadowScope) {
    importAndUse |= LOOKUP_SKIP_SHADOW_SCOPES;
  }

  if (!allowPrivateUseImp) {
    importAndUse |= LOOKUP_SKIP_PRIVATE_USE_IMPORT;
  }

  auto decls = lookupNameInScope(context, scope,
                                 /* receiver scopes */ {},
                                 fn->untyped()->name(), importAndUse);
  for (const auto& borrowedIds : decls) {
    for (const auto& id : borrowedIds) {
      if (id == fn->id()) return true;
    }
  }
  return false;
}

// Returns a distance measure used to compare the visibility
// of two functions.
//
// Enclosing scope adds 2 distance
// Shadow scope adds 1 distance
//
// Returns -1 if the function is not found here
// or if the scope was already visited.
static int
computeVisibilityDistanceInternal(Context* context, const Scope* scope,
                                  const TypedFnSignature* fn, int distance) {

  // first, check things in the current block or
  // from use/import that don't use a shadow scope
  bool foundHere = isDefinedInBlock(context, scope, fn) ||
                   isDefinedInUseImport(context, scope, fn,
                                        /* allowPrivateUseImp */ true,
                                        /* forShadowScope */ false);
  if (foundHere) {
    return distance;
  }
  // next, check anything from a use/import in the
  // current block that uses a shadow scope
  bool foundShadowHere = isDefinedInUseImport(context, scope, fn,
                                              /* allowPrivateUseImp */ true,
                                              /* forShadowScope */ true);
  if (foundShadowHere) {
    return distance+1;
  }

  // next, check parent scope, recursively
  if (const Scope* parentScope = scope->parentScope()) {
    return computeVisibilityDistanceInternal(context, parentScope, fn,
                                             distance+2);
  }

  return -1;
}

// Returns a distance measure used to compare the visibility
// of two functions.
//
// Returns -1 if the function is a method or if the function is not found
static int computeVisibilityDistance(Context* context, const Scope* scope, const TypedFnSignature* fn) {
  // is this a method?
  if (fn->untyped()->isMethod()) {
    return -1;
  }
  return computeVisibilityDistanceInternal(context, scope, fn, 0);
}

// Discard candidates with further visibility distance
// than other candidates.
// This check does not consider methods or operator methods.
static void discardWorseVisibility(const DisambiguationContext& dctx,
                                   const CandidatesVec& candidates,
                                   std::vector<bool>& discarded) {
  int minDistance = INT_MAX;
  int maxDistance = INT_MIN;

  for (size_t i = 0; i < candidates.size(); i++) {
    if (discarded[i]) {
      continue;
    }

    DisambiguationCandidate* candidate = (DisambiguationCandidate*)candidates[i];

    int distance = computeVisibilityDistance(dctx.context, dctx.callInScope, candidate->fn);
    candidate->visibilityDistance = distance;

    if (distance >= 0) {
      if (distance < minDistance) {
        minDistance = distance;
      }
      if (distance > maxDistance) {
        maxDistance = distance;
      }
    }
  }

  if (minDistance < maxDistance) {
    for (size_t i = 0; i < candidates.size(); i++) {
      if (discarded[i]) {
        continue;
      }

      const DisambiguationCandidate* candidate = candidates[i];
      int distance = candidate->visibilityDistance;
      if (distance > 0 && distance > minDistance) {
        EXPLAIN("X: Fn %d has further visibility distance\n", i);
        discarded[i] = true;
      }
    }
  }
}


static void disambiguateDiscarding(const DisambiguationContext&   dctx,
                                   const CandidatesVec& candidates,
                                   bool                         ignoreWhere,
                                   std::vector<bool>&           discarded) {
  // TODO: Implement commented code
  // if (mixesNonOpMethodsAndFunctions(candidates, DC, discarded)) {
  //   return;
  // }

  if (!dctx.useOldVisibility && !dctx.isMethodCall) {
    // If some candidates are less visible than other candidates,
    // discard those with less visibility.
    // This filter should not be applied to method calls.
    discardWorseVisibility(dctx, candidates, discarded);
  }

  // If any candidate does not require promotion,
  // eliminate candidates that do require promotion.
  discardWorsePromoting(dctx, candidates, discarded);

  // Consider the relationship among the arguments
  // Note that this part is a partial order;
  // in other words, "incomparable" is an option when comparing
  // two candidates. It should be transitive.
  // Discard any candidate that has a worse argument mapping than another
  // candidate.
  discardWorseArgs(dctx, candidates, discarded);

  // Apply further filtering to the set of candidates

  // Discard any candidate that has more implicit conversions
  // than another candidate.
  // After that, discard any candidate that has more param narrowing
  // conversions than another candidate.
  discardWorseConversions(dctx, candidates, discarded);

  if (!ignoreWhere) {
    // If some candidates have 'where' clauses and others do not,
    // discard those without 'where' clauses
    discardWorseWhereClauses(dctx, candidates, discarded);
  }
  if (dctx.useOldVisibility && !dctx.isMethodCall) {
    // If some candidates are less visible than other candidates,
    // discard those with less visibility.
    // This filter should not be applied to method calls.
    discardWorseVisibility(dctx, candidates, discarded);
  }
}

static MoreVisibleResult
computeIsMoreVisible(Context* context,
                     UniqueString callName,
                     const Scope* callInScope,
                     ID fn1Id,
                     ID fn2Id) {

  // TODO: This might be over-simplified -- see issue #19167

  // In both cases, include methods since they're considered for candidate
  // search.
  LookupConfig onlyDecls = LOOKUP_DECLS | LOOKUP_METHODS;
  LookupConfig importAndUse = LOOKUP_IMPORT_AND_USE | LOOKUP_METHODS;

  // Go up scopes to figure out which of the two IDs is
  // declared first / innermost
  for (auto curScope = callInScope;
       curScope != nullptr;
       curScope = curScope->parentScope()) {

    auto decls = lookupNameInScope(context, curScope,
                                   /* receiver scopes */ {},
                                   callName, onlyDecls);
    auto declVis = checkVisibilityInVec(context, decls, fn1Id, fn2Id);
    if (declVis != MoreVisibleResult::FOUND_NEITHER) {
      return declVis;
    }

    // otherwise, check also in use/imports
    if (curScope->containsUseImport()) {
      // TODO: this does not handle
      // use M putting M in a nearer scope than something called M
      // within the used module.
      // see issue #19219
      auto more = lookupNameInScope(context, curScope,
                                    /* receiver scopes */ {},
                                    callName, importAndUse);
      auto importUseVis = checkVisibilityInVec(context, more, fn1Id, fn2Id);
      if (importUseVis != MoreVisibleResult::FOUND_NEITHER) {
        return importUseVis;
      }
    }
  }

  return MoreVisibleResult::FOUND_NEITHER;
}


// Discard any candidate that has a worse argument mapping than another
// candidate.
static void discardWorseArgs(const DisambiguationContext& dctx,
                             const CandidatesVec& candidates,
                             std::vector<bool>& discarded) {
  int n = candidates.size();

  // If index i is set then we can skip testing function F_i because
  // we already know it can not be the best match.
  std::vector<bool> notBest(n, false);

  for (int i = 0; i < n; i++) {
    if (discarded[i]) {
      continue;
    }

    EXPLAIN("##########################\n");
    EXPLAIN("# Considering function %d #\n", i);
    EXPLAIN("##########################\n\n");

    const DisambiguationCandidate* candidate1 = candidates[i];

    bool forGenericInit = candidate1->fn->untyped()->isMethod() &&
                          (candidate1->fn->untyped()->name() == USTR("init") ||
                           candidate1->fn->untyped()->name() == USTR("init="))

    EXPLAIN_DUMP(candidate1->fn);

    if (notBest[i]) {
      EXPLAIN("Already known to not be best match.  Skipping.\n\n");
      continue;
    }

    for (int j = 0; j < n; j++) {
      if (i == j) {
        continue;
      }
      if (discarded[j]) {
        continue;
      }

      EXPLAIN("Comparing to function %d\n", j);
      EXPLAIN("-----------------------\n");

      const DisambiguationCandidate* candidate2 = candidates[j];

      EXPLAIN_DUMP(candidate2->fn);

      // Consider the relationship among the arguments
      // Note that this part is a partial order;
      // in other words, "incomparable" is an option when comparing
      // two candidates.
      int cmp = compareSpecificity(dctx, *candidate1, *candidate2, i, j, forGenericInit);

      if (cmp == 1) {
        EXPLAIN("X: Fn %d is a better match than Fn %d\n\n\n", i, j);
        notBest[j] = true;

      } else if (cmp == 2) {
        EXPLAIN("X: Fn %d is a worse match than Fn %d\n\n\n", i, j);
        notBest[i] = true;
        break;
      } else {
        if (cmp == -1) {
          EXPLAIN("X: Fn %d is incomparable with Fn %d\n\n\n", i, j);
        } else if (cmp == 0) {
          EXPLAIN("X: Fn %d is as good a match as Fn %d\n\n\n", i, j);
          if (notBest[j]) {
            notBest[i] = true;
            break;
          }
        }
      }
    }
  }

  // Now, discard any candidates that were worse than another candidate
  for (size_t i = 0; i < candidates.size(); ++i) {
    if (notBest[i]) {
      discarded[i] = true;
    }
  }
}

static void discardWorseWhereClauses(const DisambiguationContext& dctx,
                                     const CandidatesVec& candidates,
                                     std::vector<bool>& discarded) {
  // TODO: fill me in
}

static void discardWorseConversions(const DisambiguationContext& dctx,
                                    const CandidatesVec& candidates,
                                    std::vector<bool>& discarded) {
  // TODO: fill me in
}

// If any candidate does not require promotion,
// eliminate candidates that do require promotion.
static void discardWorsePromoting(const DisambiguationContext& dctx,
                                   const CandidatesVec& candidates,
                                   std::vector<bool>&  discarded) {
  // TODO: fill me in
}

static const MoreVisibleResult&
moreVisibleQuery(Context* context,
                 UniqueString callName,
                 const Scope* callInScope,
                 const PoiScope* callInPoiScope,
                 ID fn1Id,
                 ID fn2Id) {
  QUERY_BEGIN(moreVisibleQuery, context,
              callName, callInScope, callInPoiScope,
              fn1Id, fn2Id);

  MoreVisibleResult result =
    computeIsMoreVisible(context, callName, callInScope, fn1Id, fn2Id);

  for (const PoiScope* curPoi = callInPoiScope;
       curPoi != nullptr;
       curPoi = curPoi->inFnPoi()) {
    // stop if we have found one of them
    if (result != FOUND_NEITHER)
      break;

    result = computeIsMoreVisible(context, callName, curPoi->inScope(),
                                  fn1Id, fn2Id);
  }

  return QUERY_END(result);
}

/**
  Computes whether candidate1 or candidate2 is more visible/shadowing
  the other.
 */
static MoreVisibleResult
moreVisible(const DisambiguationContext& dctx,
            const DisambiguationCandidate& candidate1,
            const DisambiguationCandidate& candidate2) {
  UniqueString callName = dctx.call->name();
  ID fn1Id = candidate1.fn->id();
  ID fn2Id = candidate2.fn->id();

  // ignore more-visible for methods
  if (candidate1.fn->untyped()->isMethod() &&
      candidate2.fn->untyped()->isMethod()) {
    return FOUND_BOTH;
  }

  return moreVisibleQuery(dctx.context, callName,
                          dctx.callInScope, dctx.callInPoiScope,
                          fn1Id, fn2Id);
}

/**
  Compare two argument mappings, given a set of actual arguments, and set the
  disambiguation state appropriately.

  This function implements the argument mapping comparison component of the
  disambiguation procedure as detailed in section 13.14.3 of the Chapel
  language specification (page 107).

  actualIdx is the index within the call of the argument to be compared.

  Sets bits in DisambiguationState ds according to whether argument actualIdx
  in candidate1 vs candidate2 is a better match.

  Returns:
   -1 if the two formals are incomparable
    0 if the two formals have the same level of preference
    1 if fn1 is preferred
    2 if fn2 is preferred
 */
static int testArgMapping(const DisambiguationContext& dctx,
                          const DisambiguationCandidate& candidate1,
                          const DisambiguationCandidate& candidate2,
                          int actualIdx,
                          DisambiguationState& ds,
                          std::string& reason) {

  const FormalActual* fa1 = candidate1.formalActualMap.byActualIdx(actualIdx);
  const FormalActual* fa2 = candidate2.formalActualMap.byActualIdx(actualIdx);

  if (fa1 == nullptr || fa2 == nullptr) {

    return testOpArgMapping(dctx, candidate1, candidate2, actualIdx, ds, reason);
  }

  QualifiedType f1Type = fa1->formalType();
  QualifiedType f2Type = fa2->formalType();
  QualifiedType actualType = fa1->actualType();
  CHPL_ASSERT(actualType == fa2->actualType());

  // Give up early for out intent arguments
  // (these don't impact candidate selection)
  if (f1Type.kind() == QualifiedType::OUT ||
      f2Type.kind() == QualifiedType::OUT) {
    return -1;
  }

  // We only want to deal with the value types here, avoiding odd overloads
  // working (or not) due to _ref.
  // TODO: not sure how to reproduce this code in Dyno

  // Additionally, ignore the difference between referential tuples
  // and value tuples.
  // TODO: not sure how to reproduce this code in Dyno

  // TODO: Not sure we still need this here, based on production
  // Initializer work-around: Skip 'this' for generic initializers
  // if (dctx.call->name() == USTR("init") || dctx.call->name() == USTR("init=")) {
  //   auto nd1 = fa1->formal()->toNamedDecl();
  //   auto nd2 = fa2->formal()->toNamedDecl();
  //   if (nd1 != nullptr && nd2 != nullptr &&
  //       nd1->name() == USTR("this") && nd2->name() == USTR("this")) {
  //     if (getTypeGenericity(dctx.context, f1Type) != Type::CONCRETE &&
  //         getTypeGenericity(dctx.context, f2Type) != Type::CONCRETE) {
  //       return;
  //     }
  //   }
  // }

  bool formal1Promotes = false;
  bool formal2Promotes = false;
  bool formal1Narrows = false;
  bool formal2Narrows = false;

  QualifiedType actualScalarT = actualType;

  bool f1Param = f1Type.hasParamPtr();
  bool f2Param = f2Type.hasParamPtr();

  bool f1Instantiated = fa1->formalInstantiated();
  bool f2Instantiated = fa2->formalInstantiated();

  bool f1InstantiatedFromAny = false;
  bool f2InstantiatedFromAny = false;

  bool f1PartiallyGeneric = false;
  bool f2PartiallyGeneric = false;

  if (f1Instantiated) {
    f1InstantiatedFromAny = isFormalInstantiatedAny(candidate1, fa1);
    f1PartiallyGeneric = isFormalPartiallyGeneric(candidate1, fa1);
  }
  if (f2Instantiated) {
    f2InstantiatedFromAny = isFormalInstantiatedAny(candidate2, fa2);
    f2PartiallyGeneric = isFormalPartiallyGeneric(candidate2, fa2);
  }

  bool actualParam = actualType.isParam();
  EXPLAIN("Actual's type: ");
  EXPLAIN_DUMP(&actualType);
  if (actualParam)
    EXPLAIN(" (param)");
  EXPLAIN("\n");

  // do some EXPLAIN calls
  testArgMapHelper(dctx, *fa1, candidate1.forwardingTo,
                   &formal1Promotes, &formal1Narrows, ds, 1);

  testArgMapHelper(dctx, *fa2, candidate2.forwardingTo,
                   &formal2Promotes, &formal2Narrows, ds, 2);

  // Figure out scalar type for candidate matching
  if (formal1Promotes || formal2Promotes) {
    actualScalarT = computeActualScalarType(dctx.context, actualType);
  }

  // TODO: for sync/single use the valType

  // consider promotion
  if (!formal1Promotes && formal2Promotes) {
    reason = "no promotin vs promotes";
    return 1;
  }

  if (formal1Promotes && !formal2Promotes) {
    reason = "no promotion vs promotes";
    return 2;
  }

  // consider concrete vs generic functions
  // note: the f1Type == f2Type part here is important
  // and it prevents moving this logic out of the pairwise comparison.
  // It is important e.g. for:
  //   class Parent { }
  //   class GenericChild : Parent { type t; }
  // Here a GenericChild argument should be preferred to a Parent one
  if (f1Type == f2Type) {
    if (!f1Instantiated && f2Instantiated) {
      reason = "concrete vs generic";
      return 1;
    }

    if (f1Instantiated && !f2Instantiated) {
      reason = "concrete vs generic";
      return 2;
    }

    if (!f1InstantiatedFromAny && f2InstantiatedFromAny) {
      reason = "generic any vs partially generic/concrete";
      return 1;
    }

    if (f1InstantiatedFromAny && !f2InstantiatedFromAny) {
      reason = "generic any vs partially generic/concrete";
      return 2;
    }

    if (f1PartiallyGeneric && f2Instantiated && !f2PartiallyGeneric) {
      reason = "partially generic vs generic";
      return 1;
    }

    if (f1Instantiated && !f1PartiallyGeneric && f2PartiallyGeneric) {
      reason = "partially generic vs generic";
      return 2;
    }
  }

  if (f1Param && !f2Param) {
    reason = "param vs not";
    return 1;
  }

  if (!f1Param && f2Param) {
    reason = "param vs not";
    return 2;
  }

  if (f1Type != f2Type) {
    // to help with
    // proc f(x: int(8))
    // proc f(x: int(64))
    // f(myInt32) vs. f(1: int(32)) should behave the same
    if (actualParam) {
      if (!formal1Narrows && formal2Narrows) {
        reason = "param narrows vs not";
        return 1;
      }
      if (formal1Narrows && !formal2Narrows) {
        reason = "param narrows vs not";
        return 2;
      }
    }
    // e.g. to help with
    //   sin(1) calling the real(64) version (vs real(32) version)
    //
    //   proc f(complex(64), complex(64))
    //   proc f(complex(128), complex(128))
    //   f(1.0, 1.0i) calling the complex(128) version

    int p = prefersNumericCoercion(dctx, f1Type, f2Type, actualScalarT, reason);

    if (p == 1) {
      return 1;
    }
    if (p == 2) {
      return 2;
    }

    if (actualType == f1Type && actualType != f2Type) {
      reason = "actual type vs not";
      return 1;
    }

    if (actualType == f2Type && actualType != f1Type) {
      reason = "actual type vs not";
      return 2;
    }

    if (actualScalarT == f1Type && actualScalarT != f2Type) {
      reason = "scalar type vs not";
      return 1;
    }

    if (actualScalarT == f2Type && actualScalarT != f1Type) {
      reason = "scalar type vs not";
      return 2;
    }


    bool fn1Dispatches = moreSpecificCanDispatch(dctx, f1Type, f2Type);
    bool fn2Dispatches = moreSpecificCanDispatch(dctx, f2Type, f1Type);
    if (fn1Dispatches && !fn2Dispatches) {
      reason = "can dispatch";
      return 1;
    }
    if (!fn1Dispatches && fn2Dispatches) {
      reason = "can dispatch";
      return 2;
    }
  }

  if (f1Type == f2Type) {
    // the formals are the same in terms of preference
    return 0;
  }

  // the formals are incomparable
  return -1;
}

/**
  Compare two argument mappings, given a set of actual arguments, and set the
  disambiguation state appropriately.

  This function implements the argument mapping comparison component of the
  disambiguation procedure as detailed in section 13.14.3 of the Chapel
  language specification (page 107).

  actualIdx is the index within the call of the argument to be compared.

  Sets bits in DisambiguationState ds according to whether argument actualIdx
  in candidate1 vs candidate2 is a better match.
 */
static void testArgMapping(const DisambiguationContext& dctx,
                           const DisambiguationCandidate& candidate1,
                           const DisambiguationCandidate& candidate2,
                           int actualIdx,
                           DisambiguationState& ds) {

  EXPLAIN("\nLooking at argument %d\n", actualIdx);

  const FormalActual* fa1 = candidate1.formalActualMap.byActualIdx(actualIdx);
  const FormalActual* fa2 = candidate2.formalActualMap.byActualIdx(actualIdx);

  if (fa1 == nullptr || fa2 == nullptr) {
    // TODO: call testOpArgMapping if one was an operator but the
    // other is not
    CHPL_ASSERT(false && "TODO -- handle operator calls");
  }

  QualifiedType f1Type = fa1->formalType();
  QualifiedType f2Type = fa2->formalType();
  QualifiedType actualType = fa1->actualType();
  CHPL_ASSERT(actualType == fa2->actualType());

  // Give up early for out intent arguments
  // (these don't impact candidate selection)
  if (f1Type.kind() == QualifiedType::OUT ||
      f2Type.kind() == QualifiedType::OUT) {
    return;
  }

  // Initializer work-around: Skip 'this' for generic initializers
  if (dctx.call->name() == USTR("init") || dctx.call->name() == USTR("init=")) {
    auto nd1 = fa1->formal()->toNamedDecl();
    auto nd2 = fa2->formal()->toNamedDecl();
    if (nd1 != nullptr && nd2 != nullptr &&
        nd1->name() == USTR("this") && nd2->name() == USTR("this")) {
      if (getTypeGenericity(dctx.context, f1Type) != Type::CONCRETE &&
          getTypeGenericity(dctx.context, f2Type) != Type::CONCRETE) {
        return;
      }
    }
  }

  bool formal1Promotes = false;
  bool formal2Promotes = false;
  bool formal1Narrows = false;
  bool formal2Narrows = false;

  QualifiedType actualScalarT = actualType;

  bool f1Param = f1Type.hasParamPtr();
  bool f2Param = f2Type.hasParamPtr();

  bool f1Instantiated = fa1->formalInstantiated();
  bool f2Instantiated = fa2->formalInstantiated();

  bool f1InstantiatedFromAny = false;
  bool f2InstantiatedFromAny = false;

  bool f1PartiallyGeneric = false;
  bool f2PartiallyGeneric = false;

  if (f1Instantiated) {
    f1InstantiatedFromAny = isFormalInstantiatedAny(candidate1, fa1);
    f1PartiallyGeneric = isFormalPartiallyGeneric(candidate1, fa1);
  }
  if (f2Instantiated) {
    f2InstantiatedFromAny = isFormalInstantiatedAny(candidate2, fa2);
    f2PartiallyGeneric = isFormalPartiallyGeneric(candidate2, fa2);
  }

  bool actualParam = false;
  bool paramWithDefaultSize = false;

  // Don't enable param/ weak preferences for non-default sized param values.
  // If somebody bothered to type the param, they probably want it to stay that
  // way. This is a strategy to resolve ambiguity with e.g.
  //  +(param x:int(32), param y:int(32)
  //  +(param x:int(64), param y:int(64)
  // called with
  //  param x:int(32), param y:int(64)
  if (actualType.hasParamPtr()) {
    actualParam = true;
    paramWithDefaultSize = isNumericParamDefaultType(actualType);
  }

  EXPLAIN("Actual's type: ");
  EXPLAIN_DUMP(&actualType);
  if (actualParam)
    EXPLAIN(" (param)");
  if (paramWithDefaultSize)
    EXPLAIN(" (default)");
  EXPLAIN("\n");

  testArgMapHelper(dctx, *fa1, candidate1.forwardingTo,
                   &formal1Promotes, &formal1Narrows, ds, 1);

  testArgMapHelper(dctx, *fa2, candidate2.forwardingTo,
                   &formal2Promotes, &formal2Narrows, ds, 2);

  // Figure out scalar type for candidate matching
  if (formal1Promotes || formal2Promotes) {
    actualScalarT = computeActualScalarType(dctx.context, actualType);
  }

  // TODO: for sync/single use the valType

  const char* reason = "";
  (void) reason;
  typedef enum {
    NONE,
    WEAKEST,
    WEAKER,
    WEAK,
    STRONG
  } arg_preference_t;

  arg_preference_t prefer1 = NONE;
  arg_preference_t prefer2 = NONE;

  if (f1Type == f2Type && f1Param && !f2Param) {
    prefer1 = STRONG; reason = "same type, param vs not";

  } else if (f1Type == f2Type && !f1Param && f2Param) {
    prefer2 = STRONG; reason = "same type, param vs not";

  } else if (!formal1Promotes && formal2Promotes) {
    prefer1 = STRONG; reason = "no promotion vs promotes";

  } else if (formal1Promotes && !formal2Promotes) {
    prefer2 = STRONG; reason = "no promotion vs promotes";

  } else if (f1Type == f2Type           &&
             !f1Instantiated && f2Instantiated) {
    prefer1 = STRONG; reason = "concrete vs generic";

  } else if (f1Type == f2Type &&
             f1Instantiated && !f2Instantiated) {
    prefer2 = STRONG; reason = "concrete vs generic";

  } else if (!f1InstantiatedFromAny && f2InstantiatedFromAny) {
    prefer1 = STRONG; reason = "generic any vs partially generic/concrete";

  } else if (f1InstantiatedFromAny && !f2InstantiatedFromAny) {
    prefer2 = STRONG; reason = "generic any vs partially generic/concrete";

  } else if (f1Instantiated && f2Instantiated &&
             f1PartiallyGeneric && !f2PartiallyGeneric) {
    prefer1 = STRONG; reason = "partially generic vs generic";

  } else if (f1Instantiated && f2Instantiated &&
             !f1PartiallyGeneric && f2PartiallyGeneric) {
    prefer2 = STRONG; reason = "partially generic vs generic";

  } else if (f1Param != f2Param && f1Param) {
    prefer1 = WEAK; reason = "param vs not";

  } else if (f1Param != f2Param && f2Param) {
    prefer2 = WEAK; reason = "param vs not";

  } else if (!paramWithDefaultSize && formal2Narrows && !formal1Narrows) {
    prefer1 = WEAK; reason = "no narrows vs narrows";

  } else if (!paramWithDefaultSize && formal1Narrows && !formal2Narrows) {
    prefer2 = WEAK; reason = "no narrows vs narrows";

  } else if (!actualParam && actualType == f1Type && actualType != f2Type) {
    prefer1 = STRONG; reason = "actual type vs not";

  } else if (!actualParam && actualType == f2Type && actualType != f1Type) {
    prefer2 = STRONG; reason = "actual type vs not";

  } else if (actualScalarT == f1Type && actualScalarT != f2Type) {
    if (paramWithDefaultSize)
      prefer1 = WEAKEST;
    else if (actualParam)
      prefer1 = WEAKER;
    else
      prefer1 = STRONG;

    reason = "scalar type vs not";

  } else if (actualScalarT == f2Type && actualScalarT != f1Type) {
    if (paramWithDefaultSize)
      prefer2 = WEAKEST;
    else if (actualParam)
      prefer2 = WEAKER;
    else
      prefer2 = STRONG;

    reason = "scalar type vs not";

  } else if (prefersConvToOtherNumeric(dctx, actualScalarT, f1Type, f2Type)) {
    if (paramWithDefaultSize)
      prefer1 = WEAKEST;
    else
      prefer1 = WEAKER;

    reason = "preferred coercion to other";

  } else if (prefersConvToOtherNumeric(dctx, actualScalarT, f2Type, f1Type)) {
    if (paramWithDefaultSize)
      prefer2 = WEAKEST;
    else
      prefer2 = WEAKER;

    reason = "preferred coercion to other";

  } else if (f1Type != f2Type && moreSpecificCanDispatch(dctx, f1Type, f2Type)) {
    prefer1 = actualParam ? WEAKEST : STRONG;
    reason = "can dispatch";

  } else if (f1Type != f2Type && moreSpecificCanDispatch(dctx, f2Type, f1Type)) {
    prefer2 = actualParam ? WEAKEST : STRONG;
    reason = "can dispatch";

  } else if (f1Type.type()->isIntType() && f2Type.type()->isUintType()) {
    // This int/uint rule supports choosing between an 'int' and 'uint'
    // overload when passed say a uint(32).
    prefer1 = actualParam ? WEAKEST : STRONG;
    reason = "int vs uint";

  } else if (f2Type.type()->isIntType() && f1Type.type()->isUintType()) {
    prefer2 = actualParam ? WEAKEST : STRONG;
    reason = "int vs uint";

  }

  if (prefer1 != NONE) {
    const char* level = "";
    (void) level;
    if (prefer1 == STRONG)  { ds.fn1MoreSpecific = true;     level = "strong"; }
    if (prefer1 == WEAK)    { ds.fn1WeakPreferred = true;    level = "weak"; }
    if (prefer1 == WEAKER)  { ds.fn1WeakerPreferred = true;  level = "weaker"; }
    if (prefer1 == WEAKEST) { ds.fn1WeakestPreferred = true; level = "weakest"; }
    EXPLAIN("%s: Fn %d is %s preferred\n", reason, candidate1.idx, level);
  } else if (prefer2 != NONE) {
    const char* level = "";
    (void) level;
    if (prefer2 == STRONG)  { ds.fn2MoreSpecific = true;     level = "strong"; }
    if (prefer2 == WEAK)    { ds.fn2WeakPreferred = true;    level = "weak"; }
    if (prefer2 == WEAKER)  { ds.fn2WeakerPreferred = true;  level = "weaker"; }
    if (prefer2 == WEAKEST) { ds.fn2WeakestPreferred = true; level = "weakest"; }
    EXPLAIN("%s: Fn %d is %s preferred\n", reason, candidate2.idx, level);
  }
}

static void testArgMapHelper(const DisambiguationContext& dctx,
                             const FormalActual& fa,
                             const QualifiedType& forwardingTo,
                             bool* formalPromotes, bool* formalNarrows,
                             DisambiguationState& ds,
                             int fnNum) {

  QualifiedType actualType = fa.actualType();
  QualifiedType formalType = fa.formalType();

  // If we got to this point, actual type should be passable to the
  // formal type. (If not, it should have been filtered out when
  // filtering candidates).
  // But, here we want to check if it narrows or promotes
  // since that affects the disambiguation.

  if (forwardingTo.type() != nullptr) {
    actualType = forwardingTo;
  }
  CanPassResult result = canPass(dctx.context, actualType, formalType);
  CHPL_ASSERT(result.passes());
  *formalPromotes = result.promotes();
  *formalNarrows = result.convertsWithParamNarrowing();

  EXPLAIN("Formal %d's type: ", fnNum);
  EXPLAIN_DUMP(&formalType);
  if (*formalPromotes)
    EXPLAIN(" (promotes)");
  if (formalType.hasParamPtr())
    EXPLAIN(" (instantiated param)");
  if (*formalNarrows)
    EXPLAIN(" (narrows param)");
  EXPLAIN("\n");

  if (actualType.type() != formalType.type()) {
    if (actualType.hasParamPtr()) {
      EXPLAIN("Actual requires param coercion to match formal %d\n", fnNum);
    } else {
      EXPLAIN("Actual requires coercion to match formal %d\n", fnNum);
    }
  }
}


/** Is the formal an instantiation of the any-type, e.g.

    proc f(arg)

    or

    proc g(arg: ?t = 3)
 */
static bool isFormalInstantiatedAny(const DisambiguationCandidate& candidate,
                                    const FormalActual* fa) {

  if (candidate.fn->instantiatedFrom() != nullptr) {
    auto initial = candidate.fn->instantiatedFrom();
    CHPL_ASSERT(initial->instantiatedFrom() == nullptr);

    int formalIdx = fa->formalIdx();
    const QualifiedType& qt = initial->formalType(formalIdx);

    if (qt.type() && qt.type()->isAnyType())
      return true;
  }

  return false;
}

/**
 Is the formal partially generic, syntactically.

 Some examples:

    proc f(arg: [] int)
    proc f(arg: GenericRecord(int, integral))
    proc f(arg: (int, ?t))
 */
static bool isFormalPartiallyGeneric(const DisambiguationCandidate& candidate,
                                     const FormalActual* fa) {
  // TODO
  return false;
}

typedef enum {
  NUMERIC_TYPE_NON_NUMERIC,
  NUMERIC_TYPE_BOOL,
  NUMERIC_TYPE_ENUM,
  NUMERIC_TYPE_INT_UINT,
  NUMERIC_TYPE_REAL,
  NUMERIC_TYPE_IMAG,
  NUMERIC_TYPE_COMPLEX
} numeric_type_t;

static numeric_type_t classifyNumericType(const Type* t)
{
  if (t->isBoolType()) return NUMERIC_TYPE_BOOL;
  if (t->isEnumType()) return NUMERIC_TYPE_ENUM;
  if (t->isIntType()) return NUMERIC_TYPE_INT_UINT;
  if (t->isUintType()) return NUMERIC_TYPE_INT_UINT;
  if (t->isRealType()) return NUMERIC_TYPE_REAL;
  if (t->isImagType()) return NUMERIC_TYPE_IMAG;
  if (t->isComplexType()) return NUMERIC_TYPE_COMPLEX;

  return NUMERIC_TYPE_NON_NUMERIC;
}

static bool isDefaultInt(const Type* t) {
  if (auto tt = t->toIntType())
    return tt->isDefaultWidth();

  return false;
}

static bool isDefaultUint(const Type* t) {
  if (auto tt = t->toUintType())
    return tt->isDefaultWidth();

  return false;
}

static bool isDefaultImag(const Type* t) {
  if (auto tt = t->toImagType())
    return tt->isDefaultWidth();

  return false;
}

static bool isDefaultReal(const Type* t) {
  if (auto tt = t->toRealType())
    return tt->isDefaultWidth();

  return false;
}

static bool isDefaultComplex(const Type* t) {
  if (auto tt = t->toComplexType())
    return tt->isDefaultWidth();

  return false;
}

static int bitwidth(const Type* t) {
  if (auto tt = t->toPrimitiveType())
    return tt->bitwidth();

  return 0;
}

// Returns:
//   -1 if 't' is not a numeric type
//   0 if 't' is a default numeric type ('int' 'bool' etc)
//   n a positive integer width if 't' is a non-default numeric type
static int classifyNumericWidth(QualifiedType* qt)
{
  const Type* t = qt->type();
  // The default size counts as 0
  if (isDefaultInt(t)     ||
      isDefaultUint(t)    ||
      isDefaultReal(t)    ||
      isDefaultImag(t)    ||
      isDefaultComplex(t))
    return 0;

  // Bool size 64 should be considered the same as int 64
  // and just treat all bools the same
  // to prefer the default size (i.e. int)
  if (t->isBoolType())
    return 0;

  if (t->isIntType()  ||
      t->isUintType() ||
      t->isRealType() ||
      t->isImagType() )
    return bitwidth(t);

  if (t->isComplexType())
    return bitwidth(t) / 2;

  return -1;
}

// This method implements rules such as that a bool would prefer to
// coerce to 'int' over 'int(8)'.
// Returns
//  0 if there is no preference
//  1 if f1Type is better
//  2 if f2Type is better
static int prefersNumericCoercion(const DisambiguationContext& dctx,
                                  QualifiedType f1Qt,
                                  QualifiedType f2Qt,
                                  QualifiedType actualQt,
                                  std::string &reason) {

  const Type* actualType = actualQt.type();
  const Type* f1Type = f1Qt.type();
  const Type* f2Type = f2Qt.type();

  int acWidth = classifyNumericWidth(&actualQt);
  int f1Width = classifyNumericWidth(&f1Qt);
  int f2Width = classifyNumericWidth(&f2Qt);

  if (acWidth < 0 || f1Width < 0 || f2Width < 0) {
    // something is not a numeric type
    return 0;
  }

  numeric_type_t acKind = classifyNumericType(actualType);
  numeric_type_t f1Kind = classifyNumericType(f1Type);
  numeric_type_t f2Kind = classifyNumericType(f2Type);

  if (acKind == f1Kind && acKind != f2Kind) {
    reason = "same numeric kind";
    return 1;
  }
  if (acKind != f1Kind && acKind == f2Kind) {
    reason = "same numeric kind";
    return 2;
  }
// Otherwise, prefer the function with the same numeric width
  // as the actual. This rule helps this case:
  //
  //  proc f(arg: real(32))
  //  proc f(arg: real(64))
  //  f(myInt64)
  //
  // here we desire to call f(real(64)) e.g. for sin(1)
  //
  // Additionally, it impacts this case:
  //  proc f(a: real(32), b: real(32))
  //  proc f(a: real(64), b: real(64))
  //  f(myInt64, 1.0)
  // (it arranges for it to call the real(64) version vs the real(32) one)
  if (acWidth == f1Width && acWidth != f2Width) {
    reason = "same numeric width";
    return 1;
  }

  if (acWidth != f1Width && acWidth == f2Width) {
    reason = "same numeric width";
    return 2;
  }

  // note that if in the future we allow more numeric coercions,
  // we might need to make this function complete
  // (where currently it falls back on the "can dispatch" check
  //  in some cases). E.g. it could finish up by comparing
  // the two formal types in terms of their index in this list:
  //
  //  int(8) uint(8) int(16) uint(16) int(32) uint(32) int(64) uint(64)
  //  real(32) real(64) imag(32) real(64) complex(64) complex(128)

  return 0;
}

// Returns 'true' if we should prefer passing actual to f1Type
// over f2Type.
// This method implements rules such as that a bool would prefer to
// coerce to 'int' over 'int(8)'.
static bool prefersConvToOtherNumeric(const DisambiguationContext& dctx,
                                      QualifiedType actualQt,
                                      QualifiedType f1Qt,
                                      QualifiedType f2Qt) {

  const Type* actualType = actualQt.type();
  const Type* f1Type = f1Qt.type();
  const Type* f2Type = f2Qt.type();

  if (actualType != f1Type && actualType != f2Type) {
    // Is there any preference among coercions of the built-in type?
    // E.g., would we rather convert 'false' to :int or to :uint(8) ?

    numeric_type_t aT = classifyNumericType(actualType);
    numeric_type_t f1T = classifyNumericType(f1Type);
    numeric_type_t f2T = classifyNumericType(f2Type);

    bool aBoolEnum = (aT == NUMERIC_TYPE_BOOL || aT == NUMERIC_TYPE_ENUM);

    // Prefer e.g. bool(w1) passed to bool(w2) over passing to int (say)
    // Prefer uint(8) passed to uint(16) over passing to a real
    if (aT == f1T && aT != f2T)
      return true;
    // Prefer bool/enum cast to int over uint
    if (aBoolEnum && f1Type->isIntType() && f2Type->isUintType())
      return true;
    // Prefer bool/enum cast to default-sized int/uint over another
    // size of int/uint
    if (aBoolEnum &&
        (isDefaultInt(f1Type) || isDefaultUint(f1Type)) &&
        f2T == NUMERIC_TYPE_INT_UINT &&
        !(isDefaultInt(f2Type) || isDefaultUint(f2Type)))
      return true;
    // Prefer bool/enum/int/uint cast to a default-sized real over another
    // size of real or complex.
    if ((aBoolEnum || aT == NUMERIC_TYPE_INT_UINT) &&
        isDefaultReal(f1Type) &&
        (f2T == NUMERIC_TYPE_REAL || f2T == NUMERIC_TYPE_COMPLEX) &&
        !isDefaultReal(f2Type))
      return true;
    // Prefer bool/enum/int/uint cast to a default-sized complex over another
    // size of complex.
    if ((aBoolEnum || aT == NUMERIC_TYPE_INT_UINT) &&
        isDefaultComplex(f1Type) &&
        f2T == NUMERIC_TYPE_COMPLEX &&
        !isDefaultComplex(f2Type))
      return true;
    // Prefer real/imag cast to a same-sized complex over another size of
    // complex.
    if ((aT == NUMERIC_TYPE_REAL || aT == NUMERIC_TYPE_IMAG) &&
        f1T == NUMERIC_TYPE_COMPLEX &&
        f2T == NUMERIC_TYPE_COMPLEX &&
        bitwidth(actualType)*2 == bitwidth(f1Type) &&
        bitwidth(actualType)*2 != bitwidth(f2Type))
      return true;
  }

  return false;
}


static QualifiedType computeActualScalarType(Context* context,
                                             QualifiedType actualType) {
  // TODO: fill this in
  CHPL_UNIMPL("scalar type matching");
  return actualType;
}

static bool isNumericParamDefaultType(QualifiedType type) {
  if (auto typePtr = type.type()) {
    if (auto primType = typePtr->toPrimitiveType()) {
      return primType->isDefaultWidth();
    }
  }

  return false;
}

static bool moreSpecificCanDispatch(const DisambiguationContext& dctx,
                         QualifiedType actualType, QualifiedType formalType) {
  CanPassResult result = canPass(dctx.context, actualType, formalType);

  return result.passes();
}


} // end namespace resolution


template<> struct update<resolution::MoreVisibleResult> {
  bool operator()(resolution::MoreVisibleResult& keep,
                  resolution::MoreVisibleResult& addin) const {
    return defaultUpdateBasic(keep, addin);
  }
};

template<> struct mark<resolution::MoreVisibleResult> {
  void operator()(Context* context,
                  const resolution::MoreVisibleResult& keep) const {
    // nothing to do for enum
  }
};


} // end namespace chpl
