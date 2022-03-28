// The parallel iterator has an error handler around its body.
// It should catch errors thrown by the iterator, not by the loop body.

iter myiter() {
  yield 5;
}

iter myiter(param tag) where tag == iterKind.standalone {
  try {
    coforall idx in 1..2 {
      yield idx;
      if idx == 1 then
        throw new Error();
    }
  }
  catch err {
    writeln("myiter caught ", err);
  }
}

proc test() {
  try {
    writeln("before forall block");
    forall i in myiter() {
      if i == 2 then
        throw new Error();
    }
    writeln("after forall block");
  } catch e {
    writeln("test caught ", e);
  }
}

test();
