// Memory Management

/*
   Examples that map out the space of what a class reference can be in terms
   of the memory management characteristics: owned, shared, borrowed, and 
   unmanaged.  Also looking at the space of assignments, casts, default 
   coercions, and default initializations.

   QUESTION: do we want this to be a primer about memory management for classes?
             it could potentially be the next step after the classes primer?
*/

// Memory management is a term used in programming languages to describe when 
// and where space is allocated and deallocated for variables. For example, 
// { var i: int; } manages memory in the sense that at runtime it allocates an 
// integer in memory when it hits the var statement, and de-allocates it at 
// the end of the scope.

// Memory management is important because if a program allocates memory, but then
// does not deallocate that memory when it is done using it, then the running
// program will "leak" memory.  Memory leaks result in programs using more
// system memory resources than necessary and in some cases causing segfaults
// when the program runs out of memory.

// Chapel automatically manages the memory of data types such as ``int``s,
// ``string``s, ``range``s, ``domain``s, and ``array``s, which are all datatypes 
// built-in to Chapel.  ``Records`` are also managed in that they are allocated 
// and deallocated at the beginning and end of the scope they are declared in.  
// Also the field values in a ``record`` are copied around when they are passed 
// in and out of a function call.  However, ``record``s differ from primitive and 
// built-in datatypes in that ``record``s can have user-defined initializers 
// and deinitializers. A user-defined initializer for a ``record`` is called 
// by using a ``new`` expression. This might confuse a C++ programmer into 
// thinking that records DO need explicit programmer memory management, but 
// ``record``s do not. 

// Here is an example where a ``record`` is defined and then an instance of a
// ``record`` is declared and passed into a function.  The semantics of passing
// the ``record`` into the function are value semantics (unless the record is
// passed by ``ref``), thus it is as if the record value has been copied into
// the function and then the formal parameter copy goes out of scope at the
// end of the function.  (See the records primer for more detail 
// https://chapel-lang.org/docs/main/primers/records.html)
record MyRec {
  var name : string;
  var yearsOnTeam : int;
}
proc addYearIncorrect( person : MyRec ) {
// QUESTION: the below doesn't compile because person formal is considered const.
//           Is there no way to do this?  (If not that is actually cool.)
//  person.yearsOnTeam += 1;
  writeln("inside addYearIncorrect, person = ", person);
}
proc addYearCorrect( ref person : MyRec ) {
  person.yearsOnTeam += 1;
}

var me = new MyRec("Michelle", 1);
addYearIncorrect(me);
writeln("me MyRec instance was not updated ", me);
addYearCorrect(me);
writeln("me MyRec instance was updated when passed as a ref ", me);


// Why Chapel doesn't do class memory management the same way.
//
// For ``class`` instances, for example a node in a doubly-linked list, we
// want more than one variable (or field in a record or class) to refer to the
// same node.  Also, we want to be able to return a reference/pointer to a
// class instance so we can have a reference/pointer into a pointer-based
// data structure like a list, tree, graph, etc.  Thus, the memory allocated
// for some class instances needs to "escape" the context they were declared 
// and allocated in.

// Class decorators for memory management was added to Chapel to avoid having 
// to delete user-defined class instances to avoid memory leaks.

// OUTLINE: How Chapel programmers can manage memory on their own as a C++
// programmer might do.  Could use the doubly-linked list example.

// OUTLINE: The owned, shared, and borrowed memory management types(?).  How
// they can help out a Chapel programmer and some motivating examples.
// QUESTION: how is our list data structure implemented?

// OUTLINE: The rest of this primer(?) explores the space of what kind of
// default initializations occur for the different kinds of memory management
// reference types.  It also explores the space of default coercions, casts,
// and assignments to and from various memory management reference types that
// Chapel currently has with some discussion of what we might potentially want
// to modify for the Chapel 2.0 effort.

// OUTLINE: The default initializations for the different class reference types.

// OUTLINE: Where does nilable and non-nilable come into play?

// OUTLINE: What kind of reference can be assigned to what other kind of reference.

// OUTLINE: What kind of reference can be cast to what other kind of reference.

// OUTLINE: What kind of reference can be coerced to what other kind of reference.


//
// A class is a type that can contain variables and constants, called
// fields, as well as functions and iterators called methods.  A new
// class type is declared using the ``class`` keyword.
//
class C {
  var a, b: int;
  proc printFields() {
    writeln("a = ", a, " b = ", b);
  }
}

//
// The ``new`` keyword creates an instance of a class by calling an
// initializer. The class ``C`` above does not declare any initializers,
// and so the compiler-generated one is used. The compiler-generated
// initializer has an argument for each field in the class. Once a class
// has been initialized, its methods can be called.
//
// Classes have various memory management strategies that determine how
// they are freed.  We'll discuss these more below, but for now, know
// that ``new C(...)`` is equivalent to writing out ``new owned C(...)``
// where ``owned`` is one of these memory management strategies.
//
// A class variable can refer to an *instance* of a class.
var foo = new C(1, 3);
foo.printFields();

//
// Default output is supported so a class can be written by making a
// call to ``write`` or ``writeln``.  Default input is also supported.
//
writeln(foo);


// A class variable can refer to an *instance* of a class. Different class
// variables can refer to the same instance. For example, ``alias`` below
// refers to the same memory that stores the fields of ``foo``.
//
// We'll talk more about ``borrow`` below.
var alias = foo.borrow();
// now ``alias.b`` and ``foo.b`` refer to the same field,
// so the next line also modifies ``foo.b``
alias.b -= 1;
writeln(foo);

//
// Methods can also be defined outside of the class body by prefixing
// the method name with the class name.  All methods have an implicit
// ``this`` argument that is a reference to the class instance, or
// object.  The ``this`` argument can be used to access a field
// explicitly.  For example, in the method below, the ``this`` argument
// is used to access the ``b`` field which is otherwise shadowed by the
// ``b`` argument.
//
proc C.sum_a_b_b(b: int) {
  return a + b + this.b;
}
writeln(foo.sum_a_b_b(3));

//
// Here, a class named ``D`` is declared as a derived class from ``C``.
// This new class has all of the fields and methods from ``C``, plus any
// additional fields or methods it declares.  The ``printFields`` method
// has the same signature as a method from ``C`` -- it is overridden.
//
class D: C {
  var c = 1.2, d = 3.4;
  override proc printFields() {
    writeln("a = ", a, " b = ", b, " c = ", c, " d = ", d);
  }
}

//
// The static type of the variable ``foo``, declared above, is ``C``.
// Because the class ``D`` is derived from ``C``, the variable ``foo`` can
// reference an object of type ``D``.  If an overridden method such as
// ``printFields`` is called, it is dynamically dispatched to the method
// with the most specific dynamic type.
//
// Note that since ``foo`` is an ``owned C``, assigning to it
// will delete the previous instance "owned" by that variable.
foo = new D(3, 4);
foo.printFields();


// A class type includes a memory management strategy. The currently supported
// strategies are ``owned``, ``shared``, ``unmanaged``, and ``borrowed``.
var unm: unmanaged C = new unmanaged C();
// ``unm`` refers to a manually managed instance. It needs to have ``delete``
// called on it to free the memory.
delete unm;

var own: owned C = new owned C(1, 10);
// The instance referred to by ``own`` is deleted when it is no longer in scope.
// Only one ``owned C`` can refer to a given instance at a time, but the
// ownership can be transferred to another variable.

var own2 = new C(1, 10);
assert(own.type == own2.type);
// The example above shows that ``new C(...)`` can be used as a
// shorthand for ``new owned C(...)`` because ``owned`` is the default
// memory management strategy for classes.

var share: shared C = new shared C(1, 10);
// The instance referred to by ``share`` is reference counted -- that is,
// several ``shared C`` variables can refer to the same instance and
// will be reclaimed when the last one goes out of scope.

var tmp: borrowed C = new borrowed C(1, 10);
// The instance referred to by ``tmp`` will be deleted when it is no longer in
// scope. The ownership can't be transferred to another variable.

// It is possible to ``borrow`` from another class pointer.
// One way to do that is by calling the ``borrow()`` method directly:

var b1 = own.borrow();
// now b1 and own refer to the same instance
// it is illegal to:
//
//  * use the borrow after whatever it is borrowed from goes out of scope
//
//  * use the borrow after the instance is deleted (for example if own is assigned to)
//

// A class type without a decorator, such as ``C``, has generic management.
// The ``this`` argument of a method is generally ``borrowed C``.

// The compiler automatically adds conversion from ``owned``, ``shared``,
// or ``unmanaged`` in the process of resolving a function call,
// method call, or variable initialization.

var b2: borrowed C = own; // same as b2 = own.borrow();
own.printFields(); // same as own.borrow().printFields();
proc printSum(arg: borrowed C) {
  var sum = arg.a + arg.b;
  writeln(sum);
}
printSum(own); // same as printSum(own.borrow())

// A variable of class type cannot store ``nil`` unless it is
// declared to have nilable class type. To create a nilable class
// type, apply the ``?`` operator to another class type
var x: borrowed C?; // default-initializes to ``nil``

// Non-nilable class types can be implicitly converted to the corresponding
// nilable class type.
x = b2; // converting from borrowed C to borrowed C?

// The method printFields is available on ``borrowed C``,
// but not on ``borrowed C?``
//
// As a result, the call ``x.printFields()`` needs adjustment.
// The ``!`` operator is available to assert that an expression
// is not ``nil`` and return it as a non-nilable type. This operator
// will halt if the value is actually ``nil``.
//
// Note that when applied to an ``owned`` or ``shared`` variable, ``!`` will
// result in a borrow from that variable.
x!.printFields();

// There are a few method names that cause the method to have special
// meaning. Please see :ref:`primers-specialMethods` for details.
