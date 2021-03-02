use Set;

config param parSafe = false;
config const testIters = 8;

record testRecord {
  var dummy: int = 0;
  proc init(dummy: int=0) { this.dummy = dummy; }
}

operator :(x: int, type t: testRecord) {
  return new testRecord(x);
}

proc doTest(type eltType) {
  var s1: set(eltType, parSafe);
  var s2: set(eltType, parSafe);

  assert(s1.isDisjoint(s2));
  assert(s2.isDisjoint(s1));

  for i in 1..testIters {
    var x = i:eltType;
    s1.add(x);
  }

  assert(s1.isDisjoint(s2));
  assert(s2.isDisjoint(s1));

  for i in 1..(testIters * 2) {
    var x = i:eltType;
    s2.add(x);
  }

  assert(!s1.isDisjoint(s2));
  assert(!s2.isDisjoint(s1));

  for x in s1 do
    if s2.contains(x) then
      try! s2.remove(x);

  assert(s1.isDisjoint(s2));
  assert(s2.isDisjoint(s1));
}

doTest(int);
doTest(testRecord);

