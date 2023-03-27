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

#include "chpl/util/clang-integration.h"

// TODO: move this file to util to match the header

#include "chpl/framework/TemporaryFileResult.h"
#include "chpl/framework/query-impl.h"
#include "chpl/parsing/parsing-queries.h"
#include "chpl/uast/ExternBlock.h"

#include "../util/filesystem_help.h"

#include "clang/Basic/TargetInfo.h"
#include "clang/Driver/Compilation.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/Job.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/CompilerInvocation.h"
#include "clang/Frontend/TextDiagnosticPrinter.h"
#include "clang/Serialization/ASTReader.h"

#include "llvm/Config/llvm-config.h"
#include "llvm/Support/TargetSelect.h"
//#include "llvm/Support/VirtualFileSystem.h"

#if LLVM_VERSION_MAJOR >= 16
#include "llvm/TargetParser/Host.h"
#else
#include "llvm/Support/Host.h"
#endif

/*
#include <unistd.h> // TODO: remove
#include <iostream> // TODO: remove
#include <chrono> // TODO: remove
#include <ctime> // TODO: remove
*/

namespace chpl {
namespace util {


const std::vector<std::string>& clangFlags(Context* context) {
  QUERY_BEGIN_INPUT(clangFlags, context);
  std::vector<std::string> ret;
  return QUERY_END(ret);
}

void setClangFlags(Context* context, std::vector<std::string> flags) {
  QUERY_STORE_INPUT_RESULT(clangFlags, context, flags);
}

void initializeLlvmTargets() {
#ifdef HAVE_LLVM
  static bool targetsInited = false;
  if (targetsInited == false) {
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmPrinters();
    llvm::InitializeAllAsmParsers();

    targetsInited = true;
  }
#endif
}

#ifdef HAVE_LLVM
// Get the current clang executable path from printchplenv
static std::string getClangExe(Context* context) {
  std::string clangExe = "clang";
  auto chplEnv = context->getChplEnv();
  if (chplEnv) {
    auto it = chplEnv->find("CHPL_LLVM_CLANG_C");
    if (it != chplEnv->end()) {
      clangExe = it->second;
    }
  }
  return clangExe;
}

static std::string getChplLocaleModel(Context* context) {
  std::string result = "flat";
  auto chplEnv = context->getChplEnv();
  if (chplEnv) {
    auto it = chplEnv->find("CHPL_LOCALE_MODEL");
    if (it != chplEnv->end()) {
      result = it->second;
    }
  }

  return result;
}

static bool usingGpuLocaleModel(Context* context) {
  return getChplLocaleModel(context) == "gpu";
}
#endif

const std::vector<std::string>& getCC1Arguments(Context* context,
                                                std::vector<std::string> args,
                                                bool forGpuCodegen) {
  QUERY_BEGIN(getCC1Arguments, context, args, forGpuCodegen);

  std::vector<std::string> result;

#ifdef HAVE_LLVM
  std::string clangExe = getClangExe(context);
  std::vector<const char*> argsCstrs;

  argsCstrs.push_back(clangExe.c_str());
  for (const auto& arg : args) {
    argsCstrs.push_back(arg.c_str());
  }



  // TODO: use a different triple when cross compiling
  // TODO: look at CHPL_TARGET_ARCH
  initializeLlvmTargets();

#if 0
  // Here is how it could work with ci.generateCC1CommandLine /
  // ci.getCC1CommandLine.
  // This does not include all of the arguments that the later
  // version includes.

  // TODO: Should this call CompilerInvocation::generateCC1CommandLine ?
  auto diagOptions = new clang::DiagnosticOptions();
  auto diagClient = new clang::TextDiagnosticPrinter(llvm::errs(),
                                                     &*diagOptions);
  auto diagID = new clang::DiagnosticIDs();
  auto diags = new clang::DiagnosticsEngine(diagID, &*diagOptions, diagClient);

  clang::CompilerInvocation ci;
  clang::CompilerInvocation::CreateFromArgs(ci, argsCstrs, *diags);

  // result = ci.getCC1CommandLine();

  {
    // Set up string allocator.
    llvm::BumpPtrAllocator Alloc;
    llvm::StringSaver Strings(Alloc);
    auto SA = [&Strings](const llvm::Twine &Arg) { return Strings.save(Arg).data(); };

    // Synthesize full command line from the CompilerInvocation, including "-cc1".
    llvm::SmallVector<const char *, 32> Args{"-cc1"};
    ci.generateCC1CommandLine(Args, SA);

    // Convert arguments to the return type.
    result = std::vector<std::string>{Args.begin(), Args.end()};
  }

  delete diags;
#endif

  std::string triple = llvm::sys::getDefaultTargetTriple();
  // Create a compiler instance to handle the actual work.
  auto diagOptions = new clang::DiagnosticOptions();
  auto diagClient = new clang::TextDiagnosticPrinter(llvm::errs(),
                                                     &*diagOptions);
  auto diagID = new clang::DiagnosticIDs();
  auto diags = new clang::DiagnosticsEngine(diagID, &*diagOptions, diagClient);

  // takes ownership of all of the above
  clang::driver::Driver D(clangExe, triple, *diags);

  std::unique_ptr<clang::driver::Compilation> C(D.BuildCompilation(argsCstrs));

  clang::driver::Command* job = nullptr;

  if (usingGpuLocaleModel(context) == false) {
    // Not a CPU+GPU compilation, so just use first job.
    job = &*C->getJobs().begin();
  } else {
    // CPU+GPU compilation
    //  1st cc1 command is for the GPU
    //  2nd cc1 command is for the CPU
    for (auto &command : C->getJobs()) {
      bool isCC1 = false;
      for (const auto& arg : command.getArguments()) {
        if (0 == strcmp(arg, "-cc1")) {
          isCC1 = true;
          break;
        }
      }
      if (isCC1) {
        if (forGpuCodegen) {
          // For GPU, set job to 1st cc1 command
          if (job == NULL) job = &command;
        } else {
          // For CPU, set job to last cc1 command
          job = &command;
        }
      }
    }
  }

  if (job == nullptr) {
    context->error(Location(), "cannot find cc1 command from clang driver");
  } else {
    for (const char* arg : job->getArguments()) {
      result.push_back(arg);
    }
  }

  delete diags;

#endif

  /*
  printf("getCC1Arguments returning\n");
  for (auto arg : result) {
    printf("  %s\n", arg.c_str());
  }*/

  return QUERY_END(result);
}

/* returns the precompiled header file data
   args are the clang driver arguments
   externBlockId is the ID of the extern block containing code to precompile */
const owned<TemporaryFileResult>&
createClangPrecompiledHeader(Context* context, ID externBlockId) {
  QUERY_BEGIN(createClangPrecompiledHeader, context, externBlockId);

  owned<TemporaryFileResult> result;

  /*printf("Running createClangPrecompiledHeader tmpdir is %s\n",
         context->tmpDir().c_str());*/
  //sleep(1);

#ifdef HAVE_LLVM
  bool ok = true;
  std::string clangExe = getClangExe(context);
  std::string idStr = externBlockId.str();
  std::string tmpInput = context->tmpDir() + "/" + idStr + ".h";
  std::string tmpOutput = context->tmpDir() + "/" + idStr + ".ast";;

  const uast::AstNode* ast = parsing::idToAst(context, externBlockId);
  const uast::ExternBlock* eb = ast ? ast->toExternBlock() : nullptr;
  if (eb == nullptr) {
    ok = false;
  }

  std::error_code err = writeFile(tmpInput.c_str(), eb->code());
  if (err) {
    context->error(Location(), "Could not write to file %s: %s",
                   tmpInput.c_str(), err.message().c_str());
    ok = false;
  }

  // set the input file to match the modification of the revision file.
  // This avoids differences in the precompiled header file
  // that only reflect timestamps stored in the file, so that
  // the precompiled header file can be reused in more cases.
  err = copyModificationTime(context->tmpDirAnchorFile(), tmpInput);
  // can ignore err; failure here will just cause recomputation
#ifndef NDEBUG
  if (err) {
    fprintf(stderr, "Warning: could not set modification time for %s\n",
            tmpInput.c_str());
  }
#endif

  /*{
    llvm::sys::fs::file_status status;
    llvm::sys::fs::status(tmpInput, status);
    auto time = status.getLastModificationTime();
    auto e = time.time_since_epoch();
    //std::cout << "Modification time: " << std::ctime(&e) << "\n";
    std::cout << "Modification time: " << e.count() << "\n";
  }*/

  // TODO: this could use the clang linked with instead of spawning it
  // (although doing so is more complex to implement).

  // run clang to generate a precompiled header
  if (ok) {
    // gather args to clang
    const std::vector<std::string>& args = clangFlags(context);

    // run clang
    std::vector<std::string> command;

    command.push_back(clangExe);
    // append args to the command vector
    command.insert(command.end(), args.begin(), args.end());
    command.push_back("-x");
    command.push_back("c-header");
    command.push_back(tmpInput);
    command.push_back("-o");
    command.push_back(tmpOutput);

    /*printf("Precompiling with clang:\n");
    for (auto arg: command) {
      printf("  %s\n", arg.c_str());
    }*/

    const char* desc = "create clang precompiled header for extern block";
    int code = executeAndWait(command, desc);

    if (code != 0) {
      std::string cmd;
      for (auto& arg : command) {
        cmd.append(arg);
        cmd.append(" ");
      }
      context->error(Location(), "Could not run clang command %s", cmd.c_str());
      ok = false;
    }
  }

  // rename the generated file to the TemporaryFileResult path
  if (ok) {
    result = TemporaryFileResult::create(context,
                                         externBlockId.str(),
                                         ".ast");
    std::error_code err = llvm::sys::fs::rename(tmpOutput, result->path());
    if (err) {
      context->error(Location(), "Could not rename %s to %s",
                     tmpOutput.c_str(), result->path().c_str());
      ok = false;
      result = nullptr; // remove the incomplete result
    } else {
      // tell TemporaryFileResult we are done creating the file
      result->complete();
    }
  }

  /*printf("createClangPrecompiledHeader returning\n");
  if (result.get() != nullptr) {
    result->dump();
  }*/
#endif

  return QUERY_END(result);
}

static const bool&
precompiledHeaderContainsNameQuery(Context* context,
                                   const TemporaryFileResult* pch,
                                   UniqueString name) {
  QUERY_BEGIN(precompiledHeaderContainsNameQuery, context, pch, name);

  bool result = false;

#ifdef HAVE_LLVM

  //printf("Running precompiledHeaderContainsNameQuery %s\n", name.c_str());
  //printf("CHPL_HOME is %s\n", context->chplHome().c_str());

  if (pch != nullptr) {
    std::vector<std::string> clFlags = clangFlags(context);

    std::string dummyFile = context->chplHome() + "/runtime/etc/rtmain.c";
    clFlags.push_back(dummyFile);

    const std::vector<std::string>& cc1args =
      getCC1Arguments(context, clFlags, /* forGpuCodegen */ false);

    std::vector<const char*> cc1argsCstrs;
    cc1argsCstrs.push_back("clang-cc1");
    for (const auto& arg : cc1args) {
      if (arg != dummyFile) {
        cc1argsCstrs.push_back(arg.c_str());
      }
    }

    clang::CompilerInstance* Clang = new clang::CompilerInstance();

    auto diagOptions = new clang::DiagnosticOptions();
    auto diagClient = new clang::TextDiagnosticPrinter(llvm::errs(),
                                                       &*diagOptions);
    auto diagID = new clang::DiagnosticIDs();
    auto diags = new clang::DiagnosticsEngine(diagID, &*diagOptions, diagClient);

    Clang->setDiagnostics(diags);

    /*printf("Creating CompilerInvocation from\n");
    for (auto arg : cc1argsCstrs) {
      printf("  %s\n", arg);
    }*/

    bool success =
      clang::CompilerInvocation::CreateFromArgs(Clang->getInvocation(),
                                                cc1argsCstrs, *diags);
    CHPL_ASSERT(success);

    Clang->setTarget(clang::TargetInfo::CreateTargetInfo(Clang->getDiagnostics(), Clang->getInvocation().TargetOpts));
    Clang->createFileManager();
    Clang->createSourceManager(Clang->getFileManager());
    Clang->createPreprocessor(clang::TU_Complete);

    Clang->createASTReader();

    clang::ASTReader* astr = Clang->getASTReader().get();
    CHPL_ASSERT(astr);

    auto readResult = astr->ReadAST(pch->path(),
                                    clang::serialization::MK_PCH,
                                    clang::SourceLocation(),
                                    clang::ASTReader::ARR_None);
    if (readResult == clang::ASTReader::Success) {
      /*printf("Total identifiers %i\n", (int) astr->getTotalNumIdentifiers());
      printf("Total macros %i\n", (int) astr->getTotalNumMacros());
      printf("Total types %i\n", (int) astr->getTotalNumTypes());*/
      /*{
        printf("Looking up identifiers in %s\n", pch->path().c_str());
        clang::IdentifierIterator* it = astr->getIdentifiers();
        for (llvm::StringRef found = it->Next();
             !found.empty();
             found = it->Next()) {
          printf("  found ident %s\n", found.str().c_str());
        }
      }*/

      clang::IdentifierInfo* iid = astr->get(name.c_str());
      result = (iid != nullptr);
    }

    delete Clang;

#if 0
    auto astr = clang::ASTReader(Clang->getPreprocessor(),
                                 Clang->getModuleCache(),
                                 /* ASTContext */ nullptr
        Clang->getASTContext(),
#endif
  }
#endif

  return QUERY_END(result);
}

bool precompiledHeaderContainsName(Context* context,
                                   const TemporaryFileResult* pch,
                                   UniqueString name) {
  return precompiledHeaderContainsNameQuery(context, pch, name);
}


} // namespace util
} // namespace chpl
