/*
 * Copyright 2020-2023 Hewlett Packard Enterprise Development LP
 * Copyright 2004-2019 Cray Inc.
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

#ifndef CHPL_FRONTEND_LIB_PARSING_PARSER_YYLTYPE_H
#define CHPL_FRONTEND_LIB_PARSING_PARSER_YYLTYPE_H

#include "chpl/framework/Location.h"

// I really wanted to add constructors here, but that makes this type
// non-trivial by C++ standards...
struct TextLocation {

  // Even default values constitute a non-trivial default constructor.
  int first_line;
  int first_column;
  int last_line;
  int last_column;

  static TextLocation create() {
    return {
      .first_line   = -1,
      .first_column = -1,
      .last_line    = -1,
      .last_column  = -1,
    };
  }
};

// Forward 'TextLocation' forward as the official location type.
#define YYCHPL_LTYPE TextLocation

// Conditional because this will usually be done for us by Bison.
#ifndef YYLTYPE
  #define YYLTYPE YYCHPL_LTYPE 
#endif

#endif
