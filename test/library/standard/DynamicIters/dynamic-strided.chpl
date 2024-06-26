use DynamicIters;

for lo in 0..2 {
  for al in lo..lo+1 {
    for s in -10 .. 10 by 20 {
      var r = lo..#100 by s align al;
      var A: [r] atomic int;           // neg-stride

      for i in dynamic(r, chunkSize=5) { A[i].add(1); }
      writeln(A);
    }
  }
}

for lo in 0..2 {
  for al in lo..lo+1 {
    for s in -10 .. 10 by 20 {
      var r = lo..#100 by s align al;
      var A: [r] atomic int;           // neg-stride

      forall i in dynamic(r, chunkSize=5) with (ref A) { A[i].add(1); }
      writeln(A);
    }
  }
}

for lo in 0..2 {
  for al in lo..lo+1 {
    for s in -10 .. 10 by 20 {
      var r = lo..#100 by s align al;
      var A: [r] atomic int;           // neg-stride

      forall (i,j) in zip(dynamic(r, chunkSize=5), r) with (ref A) { assert(i==j); A[j].add(1); }
      writeln(A);
    }
  }
}

for lo in 0..2 {
  for al in lo..lo+1 {
    for s in -10 .. 10 by 20 {
      var r = lo..#100 by s align al;
      var A: [r] atomic int;           // neg-stride

      forall (i,j) in zip(r, dynamic(r, chunkSize=5)) with (ref A) { assert(i==j); A[j].add(1); }
      writeln(A);
    }
  }
}
