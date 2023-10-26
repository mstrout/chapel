#!/usr/bin/python3

# Run it with e.g.
# ./util/llvm/clang_builtin_gen.py third-party/llvm/llvm/tools/clang/include/clang/Basic/Builtins.def

import sys
import re
import os
import subprocess

clangDelegatedBuiltins = [
    "cabs",
    "cabsf",
    "cabsl",
    "cimag",
    "cimagf",
    "cimagl",
    "creal",
    "crealf",
    "creall",
    "conj",
    "conjf",
    "conjl",
]

rewrittenBuiltins = [
    # these are defined manually in chapel_libc_wrapper.h
    # rather than in the generated clang_builtins_wrapper.h
    #
    # Formerly handled cabs etc
]


# Print to stderr


chplHome = os.environ["CHPL_HOME"]

types = {
    "v": "void",
    "b": "boolean",
    "c": "char",
    "s": "short",
    "i": "int",
    "h": "half",
    "f": "float",
    "d": "double",
    "z": "size_t",
    "w": "wchar_t",
}

typePrefix = {
    "X": "_Complex",
    "L": "long",
    "S": "signed",
    "U": "unsigned",
}

typePostfix = {
    "*": "*",
    "C": "const",
    "D": "volatile",
}


def parseType(typeString):
    if len(typeString) == 0:
        return None
    res = []
    i = 0
    while i < len(typeString) and typeString[i] in typePrefix:
        res.append(typePrefix[typeString[i]])
        i += 1

    while i < len(typeString) and typeString[i] in types:
        res.append(types[typeString[i]])
        i += 1

    while i < len(typeString) and typeString[i] in typePostfix:
        res.append(typePostfix[typeString[i]])
        i += 1

    return (typeString[i:], " ".join(res))


def iterTypes(typeString):
    check = parseType(typeString)
    while check:
        rest, cur = check
        yield cur
        check = parseType(rest)


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

# Dictionary, for faster lookups
builtinsDict = dict()

WRAPPER_PREFIX = "chpl_clang_builtin_wrapper_"

class ClangBuiltin:

    def __init__(self, functionName, functionType, attrs):
        self.functionName = functionName
        self.functionType = functionType
        self.attrs = attrs

    def libmPrefixedWithBuiltin(self):
        return "F" in self.attrs


class ClangLibBuiltin(ClangBuiltin):

    def __init__(self, functionName, functionType, attrs, libHeader, supportedLangs):
        ClangBuiltin.__init__(self, functionName, functionType, attrs)
        self.libHeader = libHeader
        self.supportedLangs = supportedLangs

    def canGenerateWrapper(self):
        wrappedBuiltinName = "__builtin_" + self.functionName
        builtinCandidate = builtinsDict.get(wrappedBuiltinName)
        if builtinCandidate and builtinCandidate.libmPrefixedWithBuiltin():
            return True
        return False

    def generateWrapper(self):
        functionTypes = list(iterTypes(self.functionType))

        returnType = functionTypes[0]
        argTypes = functionTypes[1:]
        argNames = ["arg" + str(i) for i in range(len(argTypes))]

        args = [argType + " " +
                argName for (argType, argName) in zip(argTypes, argNames)]

        return ("static inline " + returnType + " " + "ADD_WRAPPER_PREFIX(" + self.functionName + ")" + "(" + ", ".join(args) + ")\n" +
                "{\n" +
                "  return " + "__builtin_" + self.functionName + "(" + ", ".join(argNames) + ");\n" +
                "}\n")

def parseLibBuiltin(b):
    regex = re.compile(
        r"LIBBUILTIN\((?P<name>\w+)[, ]+\"(?P<type>[\w*.]+)\"[, ]+\"(?P<attrs>[\w+:]+)\"[, ]+(?P<header>[\w./-]+)[, ]+(?P<langs>\w+)\)")
    result = regex.match(b)
    if(result):
        d = result.groupdict()
        return ClangLibBuiltin(d["name"], d["type"], d["attrs"], d["header"], d["langs"])
    return None


def parseBuiltin(b):
    regex = re.compile(
        r"BUILTIN\((?P<name>\w+)[, ]+\"(?P<type>[\w*.]+)\"[, ]+\"(?P<attrs>[\w+:]+)\"\)")
    result = regex.match(b)
    if(result):
        d = result.groupdict()
        return ClangBuiltin(d["name"], d["type"], d["attrs"])
    return None

def runLicenseScript(f):
  licenseScriptPath = chplHome + "/util/buildRelease/add_license_to_sources.py"
  subprocess.run([licenseScriptPath, f])

def main():
    if len(sys.argv) > 1:
        clangBuiltinsDefFile = sys.argv[1]
    else:
        print("No input file provided")
        sys.exit(1)

    # Parse Builtins.def
    with open(clangBuiltinsDefFile) as f:
        content = f.readlines()

    for line in content:
        result = None
        if line.startswith("LIBBUILTIN"):
            result = parseLibBuiltin(line)
        if line.startswith("BUILTIN"):
            result = parseBuiltin(line)
        if result:
            builtinsDict[result.functionName] = result

#define TOKENPASTE(x, y) x ## y
#define TOKENPASTE2(x, y) TOKENPASTE(x, y)

    clangBuiltinsWrapperContent = [
        "/* Generated by clang_builtin_gen.py based on clang's Builtins.def */",
        "#define ADD_WRAPPER_PREFIX(S) " + WRAPPER_PREFIX+"##S"
    ]

    for b in clangDelegatedBuiltins:
        builtinCandidate = builtinsDict.get(b)
        if builtinCandidate and builtinCandidate.canGenerateWrapper():
            clangBuiltinsWrapperContent.append(builtinCandidate.generateWrapper())
        else:
            print("Cannot generate wrapper for ", b)
            sys.exit(1)


    clangBuiltinsWrapperLocation = chplHome+"/runtime/include/llvm/clang_builtins_wrapper.h"
    with open(clangBuiltinsWrapperLocation, 'w') as f:
        f.write("\n".join(clangBuiltinsWrapperContent))

    stringify = lambda s: "\"" + s + "\""
    clangBuiltinsWrappedSetContent = [
        "/* Generated by clang_builtin_gen.py based on clang's Builtins.def */",
        "#ifdef HAVE_LLVM",
        "#include <unordered_set>",
        "#include <string>",
        "#define WRAPPER_PREFIX " + stringify(WRAPPER_PREFIX),
        "std::unordered_set<std::string> chplClangBuiltinWrappedFunctions =",
        "{",
        ",\n".join([stringify(s) for s in rewrittenBuiltins+clangDelegatedBuiltins]),
        "};\n",
        "#endif"
       ]

    clangBuiltinsWrappedSetLocation = chplHome+"/compiler/include/clangBuiltinsWrappedSet.h"
    with open(clangBuiltinsWrappedSetLocation, 'w') as f:
        f.write("\n".join(clangBuiltinsWrappedSetContent))
        f.write("\n")

    runLicenseScript(clangBuiltinsWrapperLocation)
    runLicenseScript(clangBuiltinsWrappedSetLocation)

    print("Wrapper header saved to " + clangBuiltinsWrapperLocation)
    print("Wrapper header for compiler saved to " + clangBuiltinsWrappedSetLocation)




main()
