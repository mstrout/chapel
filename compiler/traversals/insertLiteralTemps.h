#ifndef _INSERT_LITERAL_TEMPS_H_
#define _INSERT_LITERAL_TEMPS_H_

#include "traversal.h"

class InsertLiteralTemps : public Traversal {
 public:
  void postProcessExpr(Expr* expr);
};

#endif
