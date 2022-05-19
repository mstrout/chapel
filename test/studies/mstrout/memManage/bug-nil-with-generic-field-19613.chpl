// https://github.com/chapel-lang/chapel/issues/19613
//
//

const numDigits = 4;

// A num-digit binary class
class BinaryDigits {
  var digit : [1..numDigits] int = 0;
  var next : owned BinaryDigits? = nil;
}

var x = new BinaryDigits();

// A similar class that triggers a compilation bug due
// to next field being generic in terms of memory management.
class BinaryDigits2 {
  var digit : [1..numDigits] int = 0;
  var next : BinaryDigits? = nil;
}

var y = new BinaryDigits2();

