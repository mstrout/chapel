record Foo {
  proc init() {
  }

  proc init=(other: Foo) {
  }
}
proc quux(x: Foo) do return x;
var foo = new Foo();
var bar = quux(foo);
writeln(foo);
writeln(bar);
