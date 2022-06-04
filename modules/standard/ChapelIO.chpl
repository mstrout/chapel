/*
 * Copyright 2020-2022 Hewlett Packard Enterprise Development LP
 * Copyright 2004-2019 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*

Basic types and utilities in support of I/O operation.

Most of Chapel's I/O support is within the :mod:`IO` module.  This section
describes automatically included basic types and routines that support the
:mod:`IO` module.

Writing
~~~~~~~~~~~~~~~~~~~

The :proc:`writeln` function allows for a simple implementation
of a Hello World program:

.. code-block:: chapel

 writeln("Hello, World!");
 // outputs
 // Hello, World!

.. _readThis-writeThis-readWriteThis:

The readThis(), writeThis(), and readWriteThis() Methods
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When programming the input and output method for a custom data type, it is
often useful to define both the read and write routines at the same time. That
is possible to do in a Chapel program by defining a ``readWriteThis`` method,
which is a generic method expecting a single :record:`~IO.channel` argument.

In cases when the reading routine and the writing routine are more naturally
separate, or in which only one should be defined, a Chapel program can define
``readThis`` (taking in a single argument - a readable channel) and/or
``writeThis`` (taking in a single argument - a writeable channel).

If none of these routines are provided, a default version of ``readThis`` and
``writeThis`` will be generated by the compiler. If ``readWriteThis`` is
defined, the compiler will generate ``readThis`` or ``writeThis`` methods - if
they do not already exist - which call ``readWriteThis``.

Note that arguments to ``readThis`` and ``writeThis`` may represent a locked
channel; as a result, calling methods on the channel in parallel from within a
``readThis``, ``writeThis``, or ``readWriteThis`` may cause undefined behavior.
Additionally, performing I/O on a global channel that is the same channel as the
one ``readThis``, ``writeThis``, or ``readWriteThis`` is operating on can result
in a deadlock. In particular, these methods should not refer to
:var:`~IO.stdin`, :var:`~IO.stdout`, or :var:`~IO.stderr` explicitly or
implicitly (such as by calling the global :proc:`writeln` function).
Instead, these methods should only perform I/O on the channel passed as an
argument.

Because it is often more convenient to use an operator for I/O, instead of
writing

ote that the types :type:`IO.ioLiteral` and :type:`IO.ioNewline` may be useful
when using the ``<~>`` operator. :type:`IO.ioLiteral` represents some string
that must be read or written as-is (e.g. ``","`` when working with a tuple),
and :type:`IO.ioNewline` will emit a newline when writing but skip to and
consume a newline when reading. Note that these types are not included by default.


This example defines a readWriteThis method and demonstrates how ``<~>`` will
call the read or write routine, depending on the situation.

.. code-block:: chapel

  use IO;

  class IntPair {
    var x: int;
    var y: int;
    proc readWriteThis(f) throws {
      f <~> x <~> new ioLiteral(",") <~> y <~> new ioNewline();
    }
  }
  var ip = new IntPair(17,2);
  write(ip);
  // prints out
  // 17,2

This example defines a only a writeThis method - so that there will be a
function resolution error if the class NoRead is read.

.. code-block:: chapel

  class NoRead {
    var x: int;
    var y: int;
    proc writeThis(f) throws {
      f <~> "hello";
    }
    // Note that no readThis function will be generated.
  }
  var nr = new NoRead();
  write(nr);
  // prints out
  // hello

  // Note that read(nr) will generate a compiler error.

.. _default-readThis-writeThis:

Default writeThis and readThis Methods
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Default ``writeThis`` methods are created for all types for which a user-defined
``writeThis`` or ``readWriteThis`` method is not provided.  They have the
following semantics:

* for a class: outputs the values within the fields of the class prefixed by
  the name of the field and the character ``=``.  Each field is separated by a
  comma.  The output is delimited by ``{`` and ``}``.
* for a record: outputs the values within the fields of the class prefixed by
  the name of the field and the character ``=``.  Each field is separated by a
  comma.  The output is delimited by ``(`` and ``)``.

Default ``readThis`` methods are created for all types for which a user-defined
``readThis`` method is not provided.  The default ``readThis`` methods are
defined to read in the output of the default ``writeThis`` method.

Additionally, the Chapel implementation includes ``writeThis`` methods for
built-in types as follows:

* for an array: outputs the elements of the array in row-major order
  where rows are separated by line-feeds and blank lines are used to separate
  other dimensions.
* for a domain: outputs the dimensions of the domain enclosed by
  ``{`` and ``}``.
* for a range: output the lower bound of the range, output ``..``,
  then output the upper bound of the range.  If the stride of the range
  is not ``1``, output the word ``by`` and then the stride of the range.
  If the range has special alignment, output the word ``align`` and then the
  alignment.
* for tuples, outputs the components of the tuple in order delimited by ``(``
  and ``)``, and separated by commas.

These types also include ``readThis`` methods to read the corresponding format.
Note that when reading an array, the domain of the array must be set up
appropriately before the elements can be read.

.. note::

  Note that it is not currently possible to read and write circular
  data structures with these mechanisms.

 */
pragma "module included by default"
module ChapelIO {
  use ChapelBase; // for uint().
  use ChapelLocale;
  import SysBasic.{ENOERR, syserr, EFORMAT, EEOF};
  use SysError;

  // TODO -- this should probably be private
  pragma "no doc"
  proc _isNilObject(val) {
    proc helper(o: borrowed object) return o == nil;
    proc helper(o)                  return false;
    return helper(val);
  }

  use IO;

    private
    proc isIoField(x, param i) param {
      if isType(__primitive("field by num", x, i)) ||
         isParam(__primitive("field by num", x, i)) ||
         __primitive("field by num", x, i).type == nothing {
        // I/O should ignore type or param fields
        return false;
      } else {
        return true;
      }
    }

    // ch is the channel
    // x is the record/class/union
    // i is the field number of interest
    private
    proc ioFieldNameEqLiteral(ch, type t, param i) {
      var st = ch.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);
      if st == QIO_AGGREGATE_FORMAT_JSON {
        return new ioLiteral('"' +
                             __primitive("field num to name", t, i) +
                             '":');
      } else {
        return new ioLiteral(__primitive("field num to name", t, i) + " = ");
      }
    }

    private
    proc ioFieldNameLiteral(ch, type t, param i) {
      var st = ch.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);
      if st == QIO_AGGREGATE_FORMAT_JSON {
        return new ioLiteral('"' +
                             __primitive("field num to name", t, i) +
                             '"');
      } else {
        return new ioLiteral(__primitive("field num to name", t, i));
      }
    }

    pragma "no doc"
    proc writeThisFieldsDefaultImpl(writer, x:?t, inout first:bool) throws {
      param num_fields = __primitive("num fields", t);
      var isBinary = writer.binary();

      if (isClassType(t)) {
        if _to_borrowed(t) != borrowed object {
          // only write parent fields for subclasses of object
          // since object has no .super field.
          writeThisFieldsDefaultImpl(writer, x.super, first);
        }
      }

      if isExternUnionType(t) {
        compilerError("Cannot write extern union");

      } else if !isUnionType(t) {
        // print out all fields for classes and records
        for param i in 1..num_fields {
          if isIoField(x, i) {
            if !isBinary {
              var comma = new ioLiteral(", ");
              if !first then writer.write(comma);

              var eq:ioLiteral = ioFieldNameEqLiteral(writer, t, i);
              writer.writeIt(eq);
            }

            writer.writeIt(__primitive("field by num", x, i));

            first = false;
          }
        }
      } else {
        // Handle unions.
        // print out just the set field for a union.
        var id = __primitive("get_union_id", x);
        for param i in 1..num_fields {
          if isIoField(x, i) && i == id {
            if isBinary {
              // store the union ID
              write(id);
            } else {
              var eq:ioLiteral = ioFieldNameEqLiteral(writer, t, i);
              writer.writeIt(eq);
            }
            writer.writeIt(__primitive("field by num", x, i));
          }
        }
      }
    }
    // Note; this is not a multi-method and so must be called
    // with the appropriate *concrete* type of x; that's what
    // happens now with buildDefaultWriteFunction
    // since it has the concrete type and then calls this method.

    // MPF: We would like to entirely write the default writeThis
    // method in Chapel, but that seems to be a bit of a challenge
    // right now and I'm having trouble with scoping/modules.
    // So I'll go back to writeThis being generated by the
    // compiler.... the writeThis generated by the compiler
    // calls writeThisDefaultImpl.
    pragma "no doc"
    proc writeThisDefaultImpl(writer, x:?t) throws {
      if !writer.binary() {
        var st = writer.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);
        var start:ioLiteral;
        if st == QIO_AGGREGATE_FORMAT_JSON {
          start = new ioLiteral("{");
        } else if st == QIO_AGGREGATE_FORMAT_CHPL {
          start = new ioLiteral("new " + t:string + "(");
        } else {
          // the default 'braces' type
          if isClassType(t) {
            start = new ioLiteral("{");
          } else {
            start = new ioLiteral("(");
          }
        }
        writer.writeIt(start);
      }

      var first = true;

      writeThisFieldsDefaultImpl(writer, x, first);

      if !writer.binary() {
        var st = writer.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);
        var end:ioLiteral;
        if st == QIO_AGGREGATE_FORMAT_JSON {
          end = new ioLiteral("}");
        } else if st == QIO_AGGREGATE_FORMAT_CHPL {
          end = new ioLiteral(")");
        } else {
          if isClassType(t) {
            end = new ioLiteral("}");
          } else {
            end = new ioLiteral(")");
          }
        }
        writer.writeIt(end);
      }
    }

    private
    proc skipFieldsAtEnd(reader, inout needsComma:bool) throws {
      const qioFmt = reader.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);
      const isJson = qioFmt == QIO_AGGREGATE_FORMAT_JSON;
      const qioSkipUnknown = QIO_STYLE_ELEMENT_SKIP_UNKNOWN_FIELDS;
      const isSkipUnknown = reader.styleElement(qioSkipUnknown) != 0;

      if !isSkipUnknown || !isJson then return;

      while true {
        if needsComma {
          var comma = new ioLiteral(",", true);

          // Try reading a comma. If we don't, break out of the loop.
          try {
            reader.readIt(comma);
            needsComma = false;
          } catch err: BadFormatError {
            break;
          }
        }

        // Skip an unknown JSON field.


        try reader.skipField();
        needsComma = true;
      }
    }

    pragma "no doc"
    proc readThisFieldsDefaultImpl(reader, type t, ref x,
                                   inout needsComma: bool) throws
        where !isUnionType(t) {

      param numFields = __primitive("num fields", t);
      var isBinary = reader.binary();

      if isClassType(t) && _to_borrowed(t) != borrowed object {

        //
        // Only write parent fields for subclasses of object since object has
        // no .super field.
        //
        type superType = x.super.type;

        // Copy the pointer to pass it by ref.
        var castTmp: superType = x;

        try {
          // Read superclass fields.
          readThisFieldsDefaultImpl(reader, superType, castTmp,
                                    needsComma);
        } catch err {

          // TODO: Hold superclass errors or just throw immediately?
          throw err;
        }
      }

      if isBinary {

        // Binary is simple, just read all fields in order.
        for param i in 1..numFields do
          if isIoField(x, i) then
            try reader.readIt(__primitive("field by num", x, i));
      } else if numFields > 0 {

        // This tuple helps us not read the same field twice.
        var readField: (numFields) * bool;

        // These two help us know if we've read all the fields.
        var numToRead = 0;
        var numRead = 0;

        for param i in 1..numFields do
          if isIoField(x, i) then
            numToRead += 1;

        // The order should not matter.
        while numRead < numToRead {

          // Try reading a comma. If we don't, then break.
          if needsComma then
            try {
              var comma = new ioLiteral(",", true);
              reader.readIt(comma);
              needsComma = false;
            } catch err: BadFormatError {
              // Break out of the loop if we didn't read a comma.
              break;
            }

          //
          // Find a field name that matches.
          //
          // TODO: this is not particularly efficient. If we have a lot of
          // fields, this is O(n**2), and there are other potential problems
          // with string reallocation.
          // We could do better if we put the field names to scan for into
          // a regular expression, possibly with | and ( ) for capture
          // groups so we can know which field was read.
          //

          var st = reader.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);
          const qioSkipUnknown = QIO_STYLE_ELEMENT_SKIP_UNKNOWN_FIELDS;
          var isSkipUnknown = reader.styleElement(qioSkipUnknown) != 0;

          var hasReadFieldName = false;

          for param i in 1..numFields {
            if !isIoField(x, i) || hasReadFieldName || readField[i-1] then
              continue;

            var fieldName = ioFieldNameLiteral(reader, t, i);

            try {
              reader.readIt(fieldName);
            } catch err: SystemError {
              // Try reading again with a different union element.
              if err.err == EFORMAT || err.err == EEOF then continue;
              throw err;
            }

            hasReadFieldName = true;
            needsComma = true;

            var equalSign = if st == QIO_AGGREGATE_FORMAT_JSON
              then new ioLiteral(":", true)
              else new ioLiteral("=", true);

            try reader.readIt(equalSign);

            try reader.readIt(__primitive("field by num", x, i));
            readField[i-1] = true;
            numRead += 1;
          }

          const isJson = st == QIO_AGGREGATE_FORMAT_JSON;

          // Try skipping fields if we're JSON and allowed to do so.
          if !hasReadFieldName then
            if isSkipUnknown && isJson {
              try reader.skipField();
              needsComma = true;
            } else {
              throw new owned
                BadFormatError("Failed to read field, could not skip");
            }
        }

        // Check that we've read all fields, return error if not.
        if numRead == numToRead {
          // TODO: Do we throw superclass error here?
        } else {
          param tag = if isClassType(t) then "class" else "record";
          const msg = "Read only " + numRead:string + " out of "
              + numToRead:string + " fields of " + tag + " " + t:string;
          throw new owned
            BadFormatError(msg);
        }
      }
    }

    pragma "no doc"
    proc readThisFieldsDefaultImpl(reader, type t, ref x,
                                   inout needsComma: bool) throws
        where isUnionType(t) && !isExternUnionType(t) {

      param numFields = __primitive("num fields", t);
      var isBinary = reader.binary();


      if isBinary {
        var id = __primitive("get_union_id", x);

        // Read the ID.
        try reader.readIt(id);
        for param i in 1..numFields do
          if isIoField(x, i) && i == id then
            try reader.readIt(__primitive("field by num", x, i));
      } else {

        // Read the field name = part until we get one that worked.
        var hasFoundAtLeastOneField = false;

        for param i in 1..numFields {
          if !isIoField(x, i) then continue;

          var st = reader.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);
          var fieldName = ioFieldNameLiteral(reader, t, i);

          try {
            reader.readIt(fieldName);
          } catch err: SystemError {

            // Try reading again with a different union element.
            if err.err == EFORMAT || err.err == EEOF then continue;
            throw err;
          }

          hasFoundAtLeastOneField = true;

          var eq = if st == QIO_AGGREGATE_FORMAT_JSON
            then new ioLiteral(":", true)
            else new ioLiteral("=", true);

          // TODO: Why not a `read` call here?
          try readIt(eq);

          // We read the 'name = ', so now read the value!
          try reader.readIt(__primitive("field by num", x, i));
        }

        if !hasFoundAtLeastOneField then
          throw new owned
            BadFormatError("Failed to find any union fields");
      }
    }

    // Note; this is not a multi-method and so must be called
    // with the appropriate *concrete* type of x; that's what
    // happens now with buildDefaultWriteFunction
    // since it has the concrete type and then calls this method.
    pragma "no doc"
    proc readThisDefaultImpl(reader, x:?t) throws where isClassType(t) {
      const st = reader.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);

      if !reader.binary() {
        var start = if st == QIO_AGGREGATE_FORMAT_CHPL
          then new ioLiteral("new " + t:string + "(")
          else new ioLiteral("{");

        try reader.readIt(start);
      }

      var needsComma = false;

      // Make a copy of the reference that we can modify.
      var obj = x;

      try readThisFieldsDefaultImpl(reader, t, obj, needsComma);
      try skipFieldsAtEnd(reader, needsComma);

      if !reader.binary() {
        var end = if st == QIO_AGGREGATE_FORMAT_CHPL
          then new ioLiteral(")")
          else new ioLiteral("}");

        try reader.readIt(end);
      }
    }

    pragma "no doc"
    proc readThisDefaultImpl(reader, ref x:?t) throws where !isClassType(t) {
      const st = reader.styleElement(QIO_STYLE_ELEMENT_AGGREGATE);

      if !reader.binary() {
        var start: ioLiteral;

        select st {
          when QIO_AGGREGATE_FORMAT_CHPL do
            start = new ioLiteral("new " + t:string + "(");
          when QIO_AGGREGATE_FORMAT_JSON do
            start = new ioLiteral("{");
          otherwise do
            start = new ioLiteral("(");
        }

        try reader.readIt(start);
      }

      var needsComma = false;

      try readThisFieldsDefaultImpl(reader, t, x, needsComma);
      try skipFieldsAtEnd(reader, needsComma);

      if !reader.binary() {
        var end: ioLiteral = if st == QIO_AGGREGATE_FORMAT_JSON
          then new ioLiteral("}")
          else new ioLiteral(")");

        try reader.readIt(end);
      }
    }

  pragma "no doc"
  proc locale.writeThis(f) throws {
    // FIXME this doesn't resolve without `this`
    f <~> this._instance;
  }

  pragma "no doc"
  proc _ddata.writeThis(f) throws {
    compilerWarning("printing _ddata class");
    f <~> "<_ddata class cannot be printed>";
  }

  pragma "no doc"
  proc chpl_taskID_t.writeThis(f) throws {
    var tmp : uint(64) = this : uint(64);
    f <~> (tmp);
  }

  pragma "no doc"
  proc chpl_taskID_t.readThis(f) throws {
    var tmp : uint(64);
    f <~> tmp;
    this = tmp : chpl_taskID_t;
  }

  pragma "no doc"
  proc nothing.writeThis(f) {}

  // Moved here to avoid circular dependencies in ChapelTuple.
  pragma "no doc"
  proc _tuple.readWriteThis(f) throws {
    var st = f.styleElement(QIO_STYLE_ELEMENT_TUPLE);
    var start:ioLiteral;
    var comma:ioLiteral;
    var end:ioLiteral;
    var binary = f.binary();

    if st == QIO_TUPLE_FORMAT_SPACE {
      start = new ioLiteral("");
      comma = new ioLiteral(" ");
      end = new ioLiteral("");
    } else if st == QIO_TUPLE_FORMAT_JSON {
      start = new ioLiteral("[");
      comma = new ioLiteral(", ");
      end = new ioLiteral("]");
    } else {
      start = new ioLiteral("(");
      comma = new ioLiteral(", ");
      end = new ioLiteral(")");
    }

    if !binary {
      f <~> start;
    }
    if size != 0 {
      f <~> this(0);
      for param i in 1..size-1 {
        if !binary {
          f <~> comma;
        }
        f <~> this(i);
      }
    }
    if !binary {
      f <~> end;
    }
  }

  // Moved here to avoid circular dependencies in ChapelRange
  // Write implementation for ranges
  pragma "no doc"
  proc range.writeThis(f) throws
  {
    // a range with a more normalized alignment
    // a separate variable so 'this' can be const
    var alignCheckRange = this;
    if f.writing {
      alignCheckRange.normalizeAlignment();
    }

    if hasLowBound() then
      f <~> lowBound;
    f <~> new ioLiteral("..");
    if hasHighBound() {
      if (chpl__singleValIdxType(this.idxType) && this._low != this._high) {
        f <~> new ioLiteral("<") <~> lowBound;
      } else {
        f <~> highBound;
      }
    }
    if stride != 1 then
      f <~> new ioLiteral(" by ") <~> stride;

    // Write out the alignment only if it differs from natural alignment.
    // We take alignment modulo the stride for consistency.
    if ! alignCheckRange.isNaturallyAligned() && aligned then
      f <~> new ioLiteral(" align ") <~> chpl_intToIdx(chpl__mod(chpl__idxToInt(alignment), stride));
  }

  pragma "no doc"
  proc ref range.readThis(f) throws {
    if hasLowBound() then f <~> _low;

    f <~> new ioLiteral("..");

    if hasHighBound() then f <~> _high;

    if stride != 1 then f <~> new ioLiteral(" by ") <~> stride;

    try {
      f <~> new ioLiteral(" align ");

      if stridable {
        var a: intIdxType;
        f <~> a;
        _alignment = a;
      } else {
        throw new owned
          BadFormatError("Range is not stridable, cannot store alignment");
      }
    } catch err: BadFormatError {
      // Range is naturally aligned.
    }
  }

  pragma "no doc"
  override proc LocaleModel.writeThis(f) throws {
    // Most classes will define it like this:
    //      f <~> name;
    // but here it is defined thus for backward compatibility.
    f <~> new ioLiteral("LOCALE") <~> chpl_id();
  }

  /* Errors can be printed out. In that event, they will
     show information about the error including the result
     of calling :proc:`Error.message`.
  */
  pragma "no doc"
  override proc Error.writeThis(f) throws {
    var description = chpl_describe_error(this);
    f <~> description;
  }

  /* Equivalent to ``try! stdout.write``. See :proc:`IO.channel.write` */
  proc write(const args ...?n) {
    try! stdout.write((...args));
  }
  /* Equivalent to ``try! stdout.writeln``. See :proc:`IO.channel.writeln` */
  proc writeln(const args ...?n) {
    try! stdout.writeln((...args));
  }

  // documented in the arguments version.
  pragma "no doc"
  proc writeln() {
    try! stdout.writeln();
  }

  /* Equivalent to ``try! stdout.writef``. See
     :proc:`FormattedIO.channel.writef`. */
  proc writef(fmt:?t, const args ...?k):bool
      where isStringType(t) || isBytesType(t) {

    try! {
      return stdout.writef(fmt, (...args));
    }
  }
  // documented in string version
  pragma "no doc"
  proc writef(fmt:?t):bool
      where isStringType(t) || isBytesType(t) {

    try! {
      return stdout.writef(fmt);
    }
  }

  pragma "no doc"
  proc chpl_stringify_wrapper(const args ...):string {
    use IO only stringify;
    return stringify((...args));
  }

  //
  // Catch all
  //
  // Convert 'x' to a string just the way it would be written out.
  //
  // This is marked as last resort so it doesn't take precedence over
  // generated casts for types like enums
  //
  // This version only applies to non-primitive types
  // (primitive types should support :string directly)
  pragma "no doc"
  pragma "last resort"
  operator :(x, type t:string) where !isPrimitiveType(x.type) {
    return stringify(x);
  }
}
