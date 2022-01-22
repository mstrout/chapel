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

// How Chapel programmers can manage memory on their own as a C++
// programmer might do.

// In Chapel, one can manually manage class instances as one would in C++.
// The difference is that in Chapel, the fact that a reference is not managed
// by the Chapel compiler and runtime is made explicit with the unmanaged keyword.
// For example, the following code creates a list node and then deletes it.
class ListNode {
  var data : int;
  var prev, next : unmanaged ListNode;
}

// FIXME: this is causing errors similar to what John was running into with Tree
// (see slack messages about this and figure it out)
//var node1 : unmanaged ListNode = new unmanaged ListNode();
//node1 = new unmanaged ListNode();
//delete node1;

// Note that in the above example, the first instance of a ``ListNode`` is created
// but then not deleted.  Thus there is a memory leak at the reassignment of
// ``node1`` to point at another new ``ListNode``.

// Class memory management strategies were added to Chapel to avoid having 
// to delete user-defined class instances to avoid memory leaks.


// OUTLINE: The owned, shared, and borrowed memory management types(?).  How
// they can help out a Chapel programmer and some motivating examples.
// QUESTION: how is our list data structure implemented?

// OUTLINE: The rest of this primer(?) explores the space of what kind of
// default initializations occur for the different kinds of memory management
// reference types.  It also looks at when initializations and deinitializations
// occur.  It also explores the space of default coercions, casts,
// and assignments to and from various memory management reference types that
// Chapel currently has with some discussion of what we might potentially want
// to modify for the Chapel 2.0 effort.

// OUTLINE: The default initializations for the different class reference types.
class PODclass { // class with some plain old datatypes
  var str : string;
  var num : int;
}

// default initialization is that the class instance and reference var are owned
var newDefaultInit = new PODclass("newDefaultInit",1);
writeln("newDefaultInit = ", newDefaultInit);

// this works due to split init
var splitInit : PODclass; 
splitInit = new PODclass("splitInit",3);
writeln("splitInit = ", splitInit);

// All of the other cases with "var x = new <management strategy> ClassName(...)"
// pattern.
var newOwnedRef = new owned PODclass("newOwnedRef", 11);
var newSharedRef = new shared PODclass("newSharedRef", 22);
var newUnmanagedRef = new unmanaged PODclass("newUnmanagedRef", 33);
var newBorrowedRef = new borrowed PODclass("newBorrowedRef", 44);
writeln("newOwnedRef = ", newOwnedRef);
writeln("newSharedRef = ", newSharedRef);
writeln("newUnmanagedRef = ", newUnmanagedRef);
writeln("newBorrowedRef = ", newBorrowedRef);

// Creating nilable class instances.
// reference: https://chapel-lang.org/docs/main/language/spec/classes.html
// FIXME(doc): doesn't have this example in it but should
var newDefaultRefNilable = new PODclass?("newDefaultRefNilable", 01);
var newOwnedRefNilable = new owned PODclass?("newOwnedRefNilable", 21);
var newSharedRefNilable = new shared PODclass?("newSharedRefNilable", 32);
var newUnmanagedRefNilable = new unmanaged PODclass?("newUnmanagedRefNilable", 43);
var newBorrowedRefNilable = new borrowed PODclass?("newBorrowedRefNilable", 54);
writeln("newOwnedRefNilable = ", newOwnedRefNilable);
writeln("newSharedRefNilable = ", newSharedRefNilable);
writeln("newUnmanagedRefNilable = ", newUnmanagedRefNilable);
writeln("newBorrowedRefNilable = ", newBorrowedRefNilable);

// The below don't work and I get a reasonable error message about not being
// able to default-initialize nullPtr because it is non-nilable and should try 
// PODclass? instead
//var nullPtr : unmanaged PODclass;
//var nullPtr : owned PODclass;
//var nullPtr : shared PODclass;
//var nullPtr : borrowed PODclass;

// All the below work with ref vars initialized to point at a nil
var ownNullPtr : owned PODclass?;
var shareNullPtr : owned PODclass?;
var unmanagedNullPtr : unmanaged PODclass?;
var borrowedNullPtr : borrowed PODclass?;
writeln("ownNullPtr = ", ownNullPtr);
writeln("shareNullPtr = ", shareNullPtr);
writeln("unmanagedNullPtr = ", unmanagedNullPtr);
writeln("borrowedNullPtr = ", borrowedNullPtr);

// FIXME: this should work but doesn't, shouldn't owned be the default?
// get error: cannot default-initialize a variable with generic type
//var nullPtr : PODclass?;
//writeln("nullPtr = ", nullPtr);

// Nonnilable, declaring vars and initializing.
var newDefaultRefDecl : PODclass = new PODclass("newDefaultRefDecl", 7);
var newOwnedRefDecl : owned PODclass = new owned PODclass("newOwnedRefDecl", 111);
var newSharedRefDecl : shared PODclass = 
        new shared PODclass("newSharedRefDecl", 222);
var newUnmanagedRefDecl : unmanaged PODclass = 
        new unmanaged PODclass("newUnmanagedRefDecl", 333);
var newBorrowedRefDecl : borrowed PODclass = 
        new borrowed PODclass("newBorrowedRefDecl", 444);
writeln("newDefaultRefDecl = ", newDefaultRefDecl);
writeln("newOwnedRefDecl = ", newOwnedRefDecl);
writeln("newSharedRefDecl = ", newSharedRefDecl);
writeln("newUnmanagedRefDecl = ", newUnmanagedRefDecl);
writeln("newBorrowedRefDecl = ", newBorrowedRefDecl);

// Nilable, declaring vars and initializing.
var newDefaultRefNilableDecl : PODclass? = 
        new PODclass?("newDefaultRefNilableDecl", 01);
var newOwnedRefNilableDecl : owned PODclass? = 
        new owned PODclass?("newOwnedRefNilableDecl", 210);
var newSharedRefNilableDecl : shared PODclass? = 
        new shared PODclass?("newSharedRefNilableDecl", 320);
var newUnmanagedRefNilableDecl : unmanaged PODclass? = 
        new unmanaged PODclass?("newUnmanagedRefNilableDecl", 430);
var newBorrowedRefNilableDecl : borrowed PODclass? = 
        new borrowed PODclass?("newBorrowedRefNilableDecl", 540);
writeln("newOwnedRefNilableDecl = ", newOwnedRefNilableDecl);
writeln("newSharedRefNilableDecl = ", newSharedRefNilableDecl);
writeln("newUnmanagedRefNilableDecl = ", newUnmanagedRefNilableDecl);
writeln("newBorrowedRefNilableDecl = ", newBorrowedRefNilableDecl);


//==== ASSIGNMENT 
// What kind of reference can be assigned to what other kind of reference.

//---- assigning into an owned reference variable from another ref var
// from above, var newDefaultInit = new PODclass("newDefaultInit",1);
newDefaultInit = newOwnedRef;
// FIXME: will want to check that his causes deinit to be called on what
// newDefaultInit used to refer to.

// error: Cannot assign to owned PODclass from shared PODclass
//newDefaultInit = newSharedRef;

// error: Cannot assign to owned PODclass from unmanaged PODclass
//newDefaultInit = newUnmanagedRef;

// error: Cannot assign to owned PODclass from borrowed PODclass
//newDefaultInit = newBorrowedRef;

//---- assigning into an owned reference variable from a `new` expression
newDefaultInit = new owned PODclass("newOwnedExpr", 300);

// error: Cannot assign to owned PODclass from shared PODclass
//newDefaultInit = new shared PODclass("newSharedExpr", 301);

// error: Cannot assign to owned PODclass from unmanaged PODclass
//newDefaultInit = new unmanaged PODclass("newUnmanagedExpr", 302);

// error: Cannot assign to owned PODclass from borrowed PODclass
//newDefaultInit = new borrowed PODclass("newUnmanagedExpr", 303);

//---- assigning into an shared reference variable from another ref var
// from above, var newSharedRef = new shared PODclass("newSharedRef", 22);
newSharedRef = newOwnedRef;
newSharedRef = newSharedRef;

// error: Cannot assign to shared PODclass from unmanaged PODclass
//newSharedRef = newUnmanagedRef;

// error: Cannot assign to shared PODclass from borrowed PODclass
//newSharedRef = newBorrowedRef;

//---- assigning into an shared reference variable from a `new` expression
newSharedRef = new owned PODclass("newOwnedExpr", 300);
newSharedRef = new shared PODclass("newSharedExpr", 301);

// error: Cannot assign to shared PODclass from unmanaged PODclass
//newSharedRef = new unmanaged PODclass("newUnmanagedExpr", 302);

// error: Cannot assign to shared PODclass from borrowed PODclass
//newSharedRef = new borrowed PODclass("newUnmanagedExpr", 303);

//---- assigning into a unmanaged reference variable from another ref var
// from above, var newUnmanagedRef = new unmanaged PODclass("newUnmanagedRef", 33);

// error: Cannot assign to unmanaged PODclass from owned PODclass
//newUnmanagedRef = newOwnedRef;

// error: Cannot assign to unmanaged PODclass from shared PODclass
//newUnmanagedRef = newSharedRef;

newUnmanagedRef = newUnmanagedRef;

// error: Cannot assign to unmanaged PODclass from borrowed PODclass
//newUnmanagedRef = newBorrowedRef;

//---- assigning into an unmanaged reference variable from a `new` expression

// error: Cannot assign to unmanaged PODclass from owned PODclass
//newUnmanagedRef = new owned PODclass("newOwnedExpr", 300);

// error: Cannot assign to unmanaged PODclass from shared PODclass
//newUnmanagedRef = new shared PODclass("newSharedExpr", 301);

newUnmanagedRef = new unmanaged PODclass("newUnmanagedExpr", 302);

// error: Cannot assign to unmanaged PODclass from borrowed PODclass
//newUnmanagedRef = new borrowed PODclass("newUnmanagedExpr", 303);

//---- assigning into a borrowed reference variable from another ref var
// from above, var newBorrowedRef = new borrowed PODclass("newBorrowedRef", 44);

// error: Cannot assign to unmanaged PODclass from owned PODclass
newBorrowedRef = newOwnedRef;

// error: Cannot assign to unmanaged PODclass from shared PODclass
newBorrowedRef = newSharedRef;

newBorrowedRef = newUnmanagedRef;

// error: Cannot assign to unmanaged PODclass from borrowed PODclass
newBorrowedRef = newBorrowedRef;

//---- assigning into an borrowed reference variable from a `new` expression

// error: Cannot assign to unmanaged PODclass from owned PODclass
newBorrowedRef = new owned PODclass("newOwnedExpr", 300);

// error: Cannot assign to unmanaged PODclass from shared PODclass
newBorrowedRef = new shared PODclass("newSharedExpr", 301);

newBorrowedRef = new unmanaged PODclass("newUnmanagedExpr", 302);

// error: Cannot assign to unmanaged PODclass from borrowed PODclass
newBorrowedRef = new borrowed PODclass("newUnmanagedExpr", 303);




//==== What kind of reference can be cast to what other kind of reference.

//==== What kind of reference can be coerced to what other kind of reference.


//---- can I do an example to illustrate this?
// John, Can the same class instance (object) be simultaneously referred to by a 
// shared variable and an owned variable?
// Michael Ferguson  7 days ago
// Yes and no. I think it would be possible to do that - i.e. the type system 
// doesn't prevent it - if you start from an unmanaged. But "no" because it 
// would not work right. You would get a double free.

use List;

class C {
  var num : int;
  var str : string;
  var lst : list(int);
}

var unm = new unmanaged C();
// cannot initialize 'shared C' from a 'unmanaged C'
//var shr : shared C = unm;
// cannot initialize 'owned C' from a 'unmanaged C'
//var own : owned C = unm;

// error: illegal cast from unmanaged C to shared C
//var shr : shared C = unm : shared C;
// error: illegal cast from unmanaged C to owned C
//var own : owned C = unm : owned C;

// error: cannot initialize 'shared C' from a 'unmanaged C'
//var shr : shared C = new unmanaged C();

// invalid copy-initialization
// cannot initialize 'owned C' from a 'unmanaged C'
//var own : owned C = new unmanaged C();

// John, "A variable can be tagged with an MMS, but it applies to the 
// objects that the variable references. In general, the variable’s MMS 
// much match the object’s MMS, but in some cases assigning an object to 
// a variable with a different MMS causes the object’s MMS to change. 
// For example, if an `owned` object is assigned to a `shared` variable the 
// object becomes `owned`. However, assigning a `shared` object to an 
// `owned` variable is an error. I’m not sure of the reasoning behind this."

//-- can assign an owned object to a shared reference
{
  var shr : shared C = new C();
}


//-- assigning a shared class reference to an owned class reference is an error
{
  var shr = new shared C();
  // invalid copy-initialization
  // error: cannot initialize 'owned C' from a 'shared C'
  //var own : owned C = shr1;

  // error: invalid copy-initialization
  // cannot initialize 'owned C' from a 'shared C'
  //var own : owned C = new shared C();
}

