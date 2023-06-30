use BlockDist;

proc Block.printBB() {
  // The use of 'this.' in the following is a workaround for #22656
  writeln("boundingBox = ", this.boundingBox);
}

proc DefaultAssociativeDom.printTableSize() {
  writeln("tableSize = ", table.tableSize);
}

proc main() {
  var DR = {1..20};
  var BD = DR dmapped Block(DR);
  writeln(BD.dist.type:string, ".printBB()");
  BD.dist.printBB();
  writeln();

  var DA = {1, 3, 5, 6, 7, 42};
  writeln(DA.type:string, ".printTableSize()");
  DA.printTableSize();
  writeln();
}

operator :(type t: Block(?), type res: string) {
  return "I'm a Block!";
}