use CTypes, OS.POSIX;

export proc gimmePointer(x: c_ptr(int(64))) {
  var y = 4;
  memcpy(x, c_ptrTo(y), c_sizeof(y.type));
}

export proc writeInt(x: int) {
  writeln(x);
}
