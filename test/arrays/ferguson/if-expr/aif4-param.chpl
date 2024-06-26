// aif4-param.chpl
// test if-expression of arrays where the conditional
// is a param and the expressions are each function calls
// returning an array

config param param_useA = true;

proc passArray(const ref x)
{
  writeln(x);
}


var A:[1..3] int;
proc makeA() {
  A[1] = 1;
  return A;
}

var B:[1..3] int;
proc makeB() {
  B[1] = 2;
  return B;
}

proc run() {
  passArray( if param_useA then makeA() else makeB() );

  writeln(A);
  writeln(B);
}

run();
