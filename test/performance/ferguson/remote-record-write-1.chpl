use CommDiagnostics;

config const n = 100000;
record C {
  var x:int;
  var y:int;
  var z:int;
}

var A:[1..n] C;
for i in 1..n {
  A[i] = new C(i, i+1, i+2);
}

resetCommDiagnostics();
startCommDiagnostics();

on Locales[1] {
  for c in A {
    var tmp = new C(1,1,1);
    c = tmp;
  }
}

stopCommDiagnostics();

writeln(A[1]);
writeln(A[n]);

writeln(getCommDiagnostics());
