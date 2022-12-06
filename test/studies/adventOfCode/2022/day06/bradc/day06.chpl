// Concepts:
// configs (!!!)
// named ranges
// # on ranges
// string slicing (take two?)

// TODO: maybe remove while loop for blog

use IO, Set;

config const matchSize = 4;

var line: bytes;
while readLine(line) {
  const inds = 0..<(line.size-matchSize);
  for i in inds {
    var s: set(uint(8));

    for ch in line[i..#matchSize] do
      s.add(ch);

    if s.size == matchSize {
      writeln(i+matchSize);
      break;
    }
  }
}
