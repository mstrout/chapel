use CPtr;
use SysCTypes;

extern var y : c_ptr(c_int);

writeln(y[0]);
