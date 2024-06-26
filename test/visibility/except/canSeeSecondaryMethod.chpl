use secondaryMethod except other;

// Verifies that methods defined outside of the type are also allowed by
// the except

var ownA = new owned Foo(7);
var a = ownA.borrow();

writeln(a.innerMethod(3)); // Should be 21
writeln(a.outerMethod(1)); // Should be 6
