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
  var prev, next : unmanaged ListNode?;
}

var nodeA = new unmanaged ListNode(1,nil,nil);
writeln("nodeA = ", nodeA);
nodeA = new unmanaged ListNode(2,nil,nil);
writeln("nodeA = ", nodeA);
delete nodeA;

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

//==== The default initializations for the different class reference types.
class PODclass { // class with some plain old datatypes
  var str : string;
  var num : int;
}

// default initialization is that the class instance and reference var are owned
var newDefaultInit = new PODclass("newDefaultInit",1);
writeln("newDefaultInit = ", newDefaultInit);

// the below works due to split init
var splitInit : PODclass; 
splitInit = new PODclass("splitInit",2);
writeln("splitInit = ", splitInit);

// All of the other cases with "var x = new <management strategy> ClassName(...)"
// pattern.
var newOwnedRef = new owned PODclass("newOwnedRef", 3);
var newSharedRef = new shared PODclass("newSharedRef", 4);
var newUnmanagedRef = new unmanaged PODclass("newUnmanagedRef", 5);
var newBorrowedRef = new borrowed PODclass("newBorrowedRef", 6);
writeln("newOwnedRef = ", newOwnedRef);
writeln("newSharedRef = ", newSharedRef);
writeln("newUnmanagedRef = ", newUnmanagedRef);
writeln("newBorrowedRef = ", newBorrowedRef);

// Creating nilable class instances.
// reference: https://chapel-lang.org/docs/main/language/spec/classes.html
// FIXME(doc): doesn't have this example in it but should
var newDefaultRefNilable = new PODclass?("newDefaultRefNilable", 7);
var newOwnedRefNilable = new owned PODclass?("newOwnedRefNilable", 8);
var newSharedRefNilable = new shared PODclass?("newSharedRefNilable", 9);
var newUnmanagedRefNilable = new unmanaged PODclass?("newUnmanagedRefNilable", 10);
var newBorrowedRefNilable = new borrowed PODclass?("newBorrowedRefNilable", 11);
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
var newDefaultRefDecl : PODclass = new PODclass("newDefaultRefDecl", 12);
var newOwnedRefDecl : owned PODclass = new owned PODclass("newOwnedRefDecl", 13);
var newSharedRefDecl : shared PODclass = 
        new shared PODclass("newSharedRefDecl", 14);
var newUnmanagedRefDecl : unmanaged PODclass = 
        new unmanaged PODclass("newUnmanagedRefDecl", 15);
var newBorrowedRefDecl : borrowed PODclass = 
        new borrowed PODclass("newBorrowedRefDecl", 16);
writeln("newDefaultRefDecl = ", newDefaultRefDecl);
writeln("newOwnedRefDecl = ", newOwnedRefDecl);
writeln("newSharedRefDecl = ", newSharedRefDecl);
writeln("newUnmanagedRefDecl = ", newUnmanagedRefDecl);
writeln("newBorrowedRefDecl = ", newBorrowedRefDecl);

// Nilable, declaring vars and initializing.
var newDefaultRefNilableDecl : PODclass? = 
        new PODclass?("newDefaultRefNilableDecl", 17);
var newOwnedRefNilableDecl : owned PODclass? = 
        new owned PODclass?("newOwnedRefNilableDecl", 18);
var newSharedRefNilableDecl : shared PODclass? = 
        new shared PODclass?("newSharedRefNilableDecl", 19);
var newUnmanagedRefNilableDecl : unmanaged PODclass? = 
        new unmanaged PODclass?("newUnmanagedRefNilableDecl", 20);
var newBorrowedRefNilableDecl : borrowed PODclass? = 
        new borrowed PODclass?("newBorrowedRefNilableDecl", 21);
writeln("newOwnedRefNilableDecl = ", newOwnedRefNilableDecl);
writeln("newSharedRefNilableDecl = ", newSharedRefNilableDecl);
writeln("newUnmanagedRefNilableDecl = ", newUnmanagedRefNilableDecl);
writeln("newBorrowedRefNilableDecl = ", newBorrowedRefNilableDecl);


//==== ASSIGNMENT 
// What kind of reference can be assigned to what other kind of reference.
// FIXME: check if all the below is consistent with the description of
// what can be implicitly converted seen at
// https://chapel-lang.org/docs/main/language/spec/conversions.html#implicit-class-conversions

//---- assigning into an owned reference variable from another ref var
// from above, var newDefaultInit = new PODclass("newDefaultInit",1);

// error: Cannot transfer ownership from a non-nilable outer variable
// FIXME: what is going on with this?
//newDefaultInit = newOwnedRef;
// FIXME: will want to check that his causes deinit to be called on what
// newDefaultInit used to refer to.  First will need to find an example where
// this kind of assignment doesn't cause a lifetime error.

// error: Cannot assign to owned PODclass from shared PODclass
//newDefaultInit = newSharedRef;

// error: Cannot assign to owned PODclass from unmanaged PODclass
//newDefaultInit = newUnmanagedRef;

// error: Cannot assign to owned PODclass from borrowed PODclass
//newDefaultInit = newBorrowedRef;

//---- assigning into an owned reference variable from a `new` expression
newDefaultInit = new owned PODclass("newOwnedExpr", 22);
writeln("newDefaultInit = ", newDefaultInit);

// error: Cannot assign to owned PODclass from shared PODclass
//newDefaultInit = new shared PODclass("newSharedExpr", 23);

// error: Cannot assign to owned PODclass from unmanaged PODclass
//newDefaultInit = new unmanaged PODclass("newUnmanagedExpr", 24);

// error: Cannot assign to owned PODclass from borrowed PODclass
//newDefaultInit = new borrowed PODclass("newBorrowedExpr", 25);

//---- assigning into an shared reference variable from another ref var
// from above, var newSharedRef = new shared PODclass("newSharedRef", 26);

// error: Cannot transfer ownership from a non-nilable outer variable
// newSharedRef = newOwnedRef;

newSharedRef = newSharedRef;
writeln("newSharedRef = ", newSharedRef);

// error: Cannot assign to shared PODclass from unmanaged PODclass
//newSharedRef = newUnmanagedRef;

// error: Cannot assign to shared PODclass from borrowed PODclass
//newSharedRef = newBorrowedRef;

//---- assigning into an shared reference variable from a `new` expression
newSharedRef = new owned PODclass("newOwnedExpr", 27);
writeln("newSharedRef = ", newSharedRef);
newSharedRef = new shared PODclass("newSharedExpr", 28);
writeln("newSharedRef = ", newSharedRef);

// error: Cannot assign to shared PODclass from unmanaged PODclass
//newSharedRef = new unmanaged PODclass("newUnmanagedExpr", 29);

// error: Cannot assign to shared PODclass from borrowed PODclass
//newSharedRef = new borrowed PODclass("newBorrowedExpr", 30);

//---- assigning into a unmanaged reference variable from another ref var
// from above, var newUnmanagedRef = new unmanaged PODclass("newUnmanagedRef", 31);

// error: Cannot assign to unmanaged PODclass from owned PODclass
//newUnmanagedRef = newOwnedRef;

// error: Cannot assign to unmanaged PODclass from shared PODclass
//newUnmanagedRef = newSharedRef;

newUnmanagedRef = newUnmanagedRef;
writeln("newUnmanagedRef = ", newUnmanagedRef);

// error: Cannot assign to unmanaged PODclass from borrowed PODclass
//newUnmanagedRef = newBorrowedRef;

//---- assigning into an unmanaged reference variable from a `new` expression

// error: Cannot assign to unmanaged PODclass from owned PODclass
//newUnmanagedRef = new owned PODclass("newOwnedExpr", 32);

// error: Cannot assign to unmanaged PODclass from shared PODclass
//newUnmanagedRef = new shared PODclass("newSharedExpr", 33);

newUnmanagedRef = new unmanaged PODclass("newUnmanagedExpr", 34);
writeln("newUnmanagedRef = ", newUnmanagedRef);

// error: Cannot assign to unmanaged PODclass from borrowed PODclass
//newUnmanagedRef = new borrowed PODclass("newBorrowedExpr", 35);

//---- assigning into a borrowed reference variable from another ref var
var tempBorrowedRef = new borrowed PODclass("tempBorrowedRef", 36);
tempBorrowedRef = newOwnedRef;
writeln("tempBorrowedRef = ", tempBorrowedRef);

tempBorrowedRef = newSharedRef;
writeln("tempBorrowedRef = ", tempBorrowedRef);

tempBorrowedRef = newUnmanagedRef;
writeln("tempBorrowedRef = ", tempBorrowedRef);

// error: Scoped variable newBorrowedRef would outlive the value it is set to
// FIXME: huh?
//newBorrowedRef = newBorrowedRef;
tempBorrowedRef = newBorrowedRef;
writeln("tempBorrowedRef = ", tempBorrowedRef);

//---- assigning into an borrowed reference variable from a `new` expression

// error: Scoped variable newBorrowedRef would outlive the value it is set to
//newBorrowedRef = new owned PODclass("newOwnedExpr", 37);
//writeln("newBorrowedRef = ", newBorrowedRef);

// error: Scoped variable newBorrowedRef would outlive the value it is set to
//newBorrowedRef = new shared PODclass("newSharedExpr", 38);
//writeln("newBorrowedRef = ", newBorrowedRef);

newBorrowedRef = new unmanaged PODclass("newUnmanagedExpr", 39);
writeln("newBorrowedRef = ", newBorrowedRef);

newBorrowedRef = new borrowed PODclass("newBorrowedExpr", 40);
writeln("newBorrowedRef = ", newBorrowedRef);

//---- assigning into a nilable owned from other nilable references
var ownedRefNilable : owned PODclass?;
ownedRefNilable = new owned PODclass?("newOwnedRefNilable", 41);
writeln("ownedRefNilable = ", ownedRefNilable);
// error: Cannot assign to owned PODclass? from shared PODclass?
//ownedRefNilable = new shared PODclass?("newSharedRefNilable", 42);
// error: Cannot assign to owned PODclass? from unmanaged PODclass?
//ownedRefNilable = new unmanaged PODclass?("newUnmanagedRefNilable", 43);
// error: Cannot assign to owned PODclass? from borrowed PODclass?
//ownedRefNilable = new borrowed PODclass?("newBorrowedRefNilable", 44);

//---- assigning into a nilable shared from other nilable references
var sharedRefNilable : shared PODclass?;
sharedRefNilable = new owned PODclass?("newOwnedRefNilable", 45);
writeln("sharedRefNilable = ", sharedRefNilable);
sharedRefNilable = new shared PODclass?("newSharedRefNilable", 46);
writeln("sharedRefNilable = ", sharedRefNilable);
// error: Cannot assign to shared PODclass? from unmanaged PODclass?
//sharedRefNilable = new unmanaged PODclass?("newUnmanagedRefNilable", 47);
// error: Cannot assign to shared PODclass? from borrowed PODclass?
//sharedRefNilable = new borrowed PODclass?("newBorrowedRefNilable", 48);

//---- assigning into a nilable unmanaged from other nilable references
var unmanagedNilable : unmanaged PODclass?;
// error: cannot assign to a 'unmanaged PODclass?' from a 'owned PODclass?'
//unmanagedNilable = new owned PODclass?("newOwnedRefNilable", 49);
// error: cannot assign to a 'unmanaged PODclass?' from a 'shared PODclass?'
//unmanagedNilable = new shared PODclass?("newSharedRefNilable", 50);
unmanagedNilable = new unmanaged PODclass?("newUnmanagedRefNilable", 51);
writeln("unmanagedNilable = ", unmanagedNilable);
// error: Cannot assign to unmanaged PODclass? from borrowed PODclass?
//unmanagedNilable = new borrowed PODclass?("newBorrowedRefNilable", 52);

//---- assigning into a nilable borrowed from other nilable references
var borrowedNilable : borrowed PODclass?;
borrowedNilable = new owned PODclass?("newOwnedRefNilable", 53);
writeln("borrowedNilable = ", borrowedNilable);
// error: Scoped variable borrowedNilable would outlive the value it is set to
//borrowedNilable = new shared PODclass?("newSharedRefNilable", 54);
borrowedNilable = new unmanaged PODclass?("newUnmanagedRefNilable", 55);
writeln("borrowedNilable = ", borrowedNilable);
borrowedNilable = new borrowed PODclass?("newBorrowedRefNilable", 56);
writeln("borrowedNilable = ", borrowedNilable);

//---- assigning a nilable into nonnilable references
// error: invalid copy-initialization
// error: cannot initialize 'owned PODclass' from a 'owned PODclass?'
//var nonNilOwned : owned PODclass = new owned PODclass?("newOwnedRefNilable", 57);
// error: invalid copy-initialization
// error: cannot initialize 'shared PODclass' from a 'shared PODclass?'
//var nonNilShared: shared PODclass=new shared PODclass?("newSharedRefNilable",58);

// FIXME: why are both the below inconsistent with the above two?
// error: cannot initialize variable 'nonNilUnmanaged' of non-nilable type 
// 'unmanaged PODclass' from a nilable 'unmanaged PODclass?'
//var nonNilUnmanaged:unmanaged PODclass = 
//        new unmanaged PODclass?("newUnmanagedRefNilable", 59);
// error: cannot initialize variable 'nonNilBorrowed' of non-nilable type 
// 'borrowed PODclass' from a nilable 'borrowed PODclass?'
//var nonNilBorrowed : borrowed PODclass =
//        new borrowed PODclass?("newBorrowedRefNilable", 60);

// error: invalid copy-initialization
// error: cannot initialize 'shared PODclass' from a 'shared PODclass?'
//var sharedRef = new shared PODclass("sharedRef", 61);;
//sharedRef = new shared PODclass?("newSharedRefNilable", 62);
// using split-init instead get the same error
// FIXME: why doesn't this work like var nonNilOwned above?
//var sharedRef : shared PODclass;
//sharedRef = new shared PODclass?("newSharedRefNilable", 63);

var unmanagedRef = new unmanaged PODclass("unmanagedRef", 64);
// error: cannot assign to a non-nilable 'unmanaged PODclass' from a nilable 
//'unmanaged PODclass?
// unmanagedRef = new unmanaged PODclass?("newUnmanagedRefNilable", 65);

//==== postfix ! operator to return a nilable type if value is not nil
// reference: https://chapel-lang.org/docs/main/language/spec/classes.html?highlight=nilable
// "The postfix ! operator converts a class value to a non-nilable type. If the 
// value is not nil, it returns a copy of that value if it is borrowed or 
// unmanaged, or a borrow from it if it is owned or shared. If the value is 
// in fact nil, it halts."

{
  var localNilOwned : owned PODclass? = new owned PODclass?("localNilOwned",66);
  var localNonNilOwned = new owned PODclass("localNonNilOwned", 67);
  // error: Cannot assign to owned PODclass from borrowed PODclass
  //localNonNilOwned = localNilOwned!;
  var localNonNilBorrowed : borrowed PODclass = localNilOwned!;
  writeln("localNonNilBorrowed = ", localNonNilBorrowed);
  // error: cannot initialize variable 'localNonNilUnmanaged' of type 
  // 'unmanaged PODclass' from a 'borrowed PODclass'
  //var localNonNilUnmanaged : unmanaged PODclass = localNilOwned!;

  var localNilShared: shared PODclass? = new shared PODclass?("localNilShared",68);
  var localNonNilBorrowed2 : borrowed PODclass = localNilShared!;
  writeln("localNonNilBorrowed2 = ", localNonNilBorrowed2);
  // error: cannot initialize variable 'localNonNilUnmanaged2' of type 
  // 'unmanaged PODclass' from a 'borrowed PODclass'
  //var localNonNilUnmanaged2 : unmanaged PODclass = localNilShared!;
}

// error: invalid copy-initialization
// error: cannot initialize 'shared PODclass' from a 'borrowed PODclass'
// NOTE: getting this error because can't assign a borrowed ref into shared
//var nonNilShared2 : shared PODclass=
//        (new shared PODclass?("newSharedRefNilable", 69))!;

var nonNilUnmanaged2:unmanaged PODclass = 
        (new unmanaged PODclass?("newUnmanagedRefNilable", 70))!;
writeln("nonNilUnmanaged2 = ", nonNilUnmanaged2);
var nonNilBorrowed2 : borrowed PODclass =
        (new borrowed PODclass?("newBorrowedRefNilable", 71))!;
writeln("nonNilBorrowed2 = ", nonNilBorrowed2);


// error: invalid copy-initialization
// error: cannot initialize 'owned PODclass' from a 'borrowed PODclass'
//var nonNilOwned2 : owned PODclass = 
//        (new owned PODclass?("newOwnedRefNilable", 72))!;
//writeln("nonNilOwned2 = ", nonNilOwned2);


//==== using borrow()
// reference: https://chapel-lang.org/docs/main/language/spec/classes.html#class-lifetime-and-borrows
// Potential issues (FIXME)
//   - "The .borrow() method is available on all class types (including 
//     unmanaged and borrowed) in order to support generic programming."
//   - "For nilable class types, it returns the borrowed nilable class type."
//     What about non-nilable?
//   - "When borrowed is used as a memory management strategy in a 
//     new-expression, it also creates an instance that has its lifetime 
//     managed by the compiler (Class New)."

var ownedRefNonNil = new owned PODclass("ownedRefNonNil", 73);
var sharedRefNonNil = new shared PODclass("sharedRefNonNil", 74);
var unmanagedRefNonNil = new unmanaged PODclass("unmanagedRefNonNil", 75);
var borrowedRefNonNil = new borrowed PODclass("borrowedRefNonNil", 76);

var borrowRefNonNilA : borrowed PODclass = ownedRefNonNil.borrow();
writeln("borrowRefNonNilA = ", borrowRefNonNilA);
var borrowRefNonNilB : borrowed PODclass = sharedRefNonNil.borrow();
writeln("borrowRefNonNilB = ", borrowRefNonNilB);
var borrowRefNonNilC : borrowed PODclass = unmanagedRefNonNil.borrow();
writeln("borrowRefNonNilC = ", borrowRefNonNilC);
var borrowRefNonNilD : borrowed PODclass = borrowedRefNonNil.borrow();
writeln("borrowRefNonNilD = ", borrowRefNonNilD);

//==== What kind of reference can be cast to what other kind of reference.
// reference: https://chapel-lang.org/docs/main/language/spec/conversions.html#explicit-class-conversions

{ // putting into a scope to avoid problem of not being able to transfer 
  // ownership from an outer variable

  var defaultRef1 = new PODclass("defaultRef1", 77);
  writeln("defaultRef1 = ", defaultRef1);
  var ownedRefNonNilCast      = defaultRef1 : owned;
  writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  // 489 error: Illegal use of dead value
  // 487 note: 'defaultRef1' is dead due to ownership transfer here
  // 489: error: mention of non-nilable variable after ownership is transferred out of it
  // 487: note: ownership transfer occurred here
  //writeln("defaultRef1 after cast = ", defaultRef1);

  // error: Cannot change class type in conversion from 'owned PODclass' to 
  // 'shared PODclass?'
  //var sharedRefNonNilCast     = defaultRef : shared;

  var defaultRef2 = new PODclass("defaultRef2", 78);
  writeln("defaultRef2 = ", defaultRef2);
  var unmanagedRefNonNilCast  = defaultRef2 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  // FIXME: should defaultRef2 lose ownership?
  writeln("defaultRef2 after cast = ", defaultRef2);

  var defaultRef3 = new PODclass("defaultRef3", 79);
  writeln("defaultRef3 = ", defaultRef3);
  var borrowedRefNonNilCast   = defaultRef3 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("defaultRef3 after cast = ", defaultRef3);

  var defaultRef4 = new PODclass("defaultRef4", 80);
  writeln("defaultRef4 = ", defaultRef4);
  var ownedRefNilCast         = defaultRef4 : owned PODclass?;
  writeln("ownedRefNilCast = ", ownedRefNilCast);
  // error: Illegal use of dead value
  // same 4 messages as example above
  //writeln("defaultRef4 after cast = ", defaultRef4);

  // error: Cannot change class type in conversion from 'owned PODclass' to 
  // 'shared PODclass?'
  //var sharedRefNilCast        = defaultRef : shared PODclass?;

  var defaultRef5 = new PODclass("defaultRef5", 81);
  writeln("defaultRef5 = ", defaultRef5);
  var unmanagedRefNilCast     = defaultRef5 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  // FIXME: should defaultRef5 lose ownership?
  writeln("defaultRef5 after cast = ", defaultRef5);

  var defaultRef6 = new PODclass("defaultRef6", 82);
  writeln("defaultRef6 = ", defaultRef6);
  var borrowedRefNilCast      = defaultRef6 : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("defaultRef6 after cast = ", defaultRef6);
}
//==== casting a shared reference into variables
{ // putting in scope to reuse some var names

  // casting shared to own
  //var sharedRef1 = new shared PODclass("sharedRef1", 83);
  //writeln("sharedRef1 = ", sharedRef1);
  // error: illegal cast from shared PODclass to owned
  //var ownedRefNonNilCast      = sharedRef1 : owned;
  //writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  //writeln("sharedRef1 after cast = ", sharedRef1);

  // casting shared to shared
  var sharedRef2 = new shared PODclass("sharedRef2", 84);
  writeln("sharedRef2 = ", sharedRef2);
  var sharedRefNonNilCast     = sharedRef2 : shared;
  writeln("sharedRefNonNilCast = ", sharedRefNonNilCast);
  writeln("sharedRef2 after cast = ", sharedRef2);

  // FIXME: should the below work?
  var sharedRef3 = new shared PODclass("sharedRef3", 85);
  writeln("sharedRef3 = ", sharedRef3);
  var unmanagedRefNonNilCast  = sharedRef3 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  writeln("sharedRef3 after cast = ", sharedRef3);

  var sharedRef4 = new shared PODclass("sharedRef4", 86);
  writeln("sharedRef4 = ", sharedRef4);
  var borrowedRefNonNilCast   = sharedRef4 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("sharedRef4 after cast = ", sharedRef4);

  //var sharedRef5 = new shared PODclass("sharedRef5", 87);
  //writeln("sharedRef5 = ", sharedRef5);
  // error: illegal cast from shared PODclass to owned PODclass?
  //var ownedRefNilCast         = sharedRef5 : owned PODclass?;
  //writeln("ownedRefNilCast = ", ownedRefNilCast);
  //writeln("sharedRef5 after cast = ", sharedRef5);

  var sharedRef6 = new shared PODclass("sharedRef6", 88);
  writeln("sharedRef6 = ", sharedRef6);
  var sharedRefNilCast        = sharedRef6 : shared PODclass?;
  writeln("sharedRefNilCast = ", sharedRefNilCast);
  writeln("sharedRef6 after cast = ", sharedRef6);

  // FIXME: should the below work?
  var sharedRef7 = new shared PODclass("sharedRef7", 89);
  writeln("sharedRef7 = ", sharedRef7);
  var unmanagedRefNilCast     = sharedRef7 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  writeln("sharedRef7 after cast = ", sharedRef7);

  var sharedRef8 = new shared PODclass("sharedRef8", 90);
  writeln("sharedRef8 = ", sharedRef8);
  var borrowedRefNilCast      = sharedRef8 : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("sharedRef8 after cast = ", sharedRef8);
}
//==== casting an unmanaged reference into variables
{ // putting in scope to reuse some var names

  // casting unmanaged to owned
  //var unmanagedRef1 = new unmanaged PODclass("unmanagedRef1", 91);
  //writeln("unmanagedRef1 = ", unmanagedRef1);
  // FIXME: I expected this to work.  Why doesn't it?
  // error: illegal cast from unmanaged PODclass to owned
  //var ownedRefNonNilCast      = unmanagedRef1 : owned;
  //writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  //writeln("unmanagedRef1 after cast = ", unmanagedRef1);

  // casting unmanaged to shared
  //var unmanagedRef2 = new unmanaged PODclass("unmanagedRef2", 92);
  //writeln("unmanagedRef2 = ", unmanagedRef2);
  // FIXME: I expected this to work as well.
  // error: illegal cast from unmanaged PODclass to shared
  //var sharedRefNonNilCast     = unmanagedRef2 : shared;
  //writeln("sharedRefNonNilCast = ", sharedRefNonNilCast);
  //writeln("unmanagedRef2 after cast = ", unmanagedRef2);

  // casting unmanaged to unmanaged
  var unmanagedRef3 = new unmanaged PODclass("unmanagedRef3", 93);
  writeln("unmanagedRef3 = ", unmanagedRef3);
  var unmanagedRefNonNilCast  = unmanagedRef3 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  writeln("unmanagedRef3 after cast = ", unmanagedRef3);

  // casting unmanaged to borrowed
  var unmanagedRef4 = new unmanaged PODclass("unmanagedRef4", 94);
  writeln("unmanagedRef4 = ", unmanagedRef4);
  var borrowedRefNonNilCast   = unmanagedRef4 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("unmanagedRef4 after cast = ", unmanagedRef4);

  // casting unmanaged to owned nilable
  //var unmanagedRef5 = new unmanaged PODclass("unmanagedRef5", 95);
  //writeln("unmanagedRef5 = ", unmanagedRef5);
  // FIXME: I expected this to work
  // error: illegal cast from unmanaged PODclass to owned PODclass?
  //var ownedRefNilCast         = unmanagedRef5 : owned PODclass?;
  //writeln("ownedRefNilCast = ", ownedRefNilCast);
  //writeln("unmanagedRef5 after cast = ", unmanagedRef5);

  // casting unmanaged to shared nilable
  //var unmanagedRef6 = new unmanaged PODclass("unmanagedRef6", 96);
  //writeln("unmanagedRef6 = ", unmanagedRef6);
  // FIXME: I expected this to work
  // error: illegal cast from unmanaged PODclass to shared PODclass?
  //var sharedRefNilCast        = unmanagedRef : shared PODclass?;
  //writeln("sharedRefNilCast = ", sharedRefNilCast);
  //writeln("unmanagedRef6 after cast = ", unmanagedRef6);

  // casting unmanaged to unmanaged nilable
  var unmanagedRef7 = new unmanaged PODclass("unmanagedRef7", 97);
  writeln("unmanagedRef7 = ", unmanagedRef);
  var unmanagedRefNilCast     = unmanagedRef7 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  writeln("unmanagedRef7 after cast = ", unmanagedRef7);

  // casting unmanaged to borrowed nilable
  var unmanagedRef8 = new unmanaged PODclass("unmanagedRef8", 98);
  writeln("unmanagedRef8 = ", unmanagedRef8);
  var borrowedRefNilCast      = unmanagedRef : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("unmanagedRef8 after cast = ", unmanagedRef8);
}

//==== casting a borrowed reference into variables
{ // putting in scope to reuse some var names

  // casting borrowed to owned
  //var borrowedRef1 = new borrowed PODclass("borrowedRef1", 99);
  //writeln("borrowedRef1 = ", borrowedRef1);
  // error: illegal cast from borrowed PODclass to owned
  //var ownedRefNonNilCast      = borrowedRef1 : owned;
  //writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  //writeln("borrowedRef1 after cast = ", borrowedRef1);

  // casting borrowed to shared
  //var borrowedRef2 = new borrowed PODclass("borrowedRef2", 100);
  //writeln("borrowedRef2 = ", borrowedRef2);
  // error: illegal cast from borrowed PODclass to shared
  //var sharedRefNonNilCast     = borrowedRef2 : shared;
  //writeln("sharedRefNonNilCast = ", sharedRefNonNilCast);
  //writeln("borrowedRef2 after cast = ", borrowedRef2);

  // casting borrowed to unmanaged
  var borrowedRef3 = new borrowed PODclass("borrowedRef3", 101);
  writeln("borrowedRef3 = ", borrowedRef3);
  var unmanagedRefNonNilCast  = borrowedRef3 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  writeln("borrowedRef3 after cast = ", borrowedRef3);

  // casting borrowed to borrowed
  var borrowedRef4 = new borrowed PODclass("borrowedRef4", 102);
  writeln("borrowedRef4 = ", borrowedRef4);
  var borrowedRefNonNilCast   = borrowedRef4 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("borrowedRef4 after cast = ", borrowedRef4);

  // casting borrowed to owned nilable
  //var borrowedRef5 = new borrowed PODclass("borrowedRef5", 103);
  //writeln("borrowedRef5 = ", borrowedRef5);
  // error: illegal cast from borrowed PODclass to owned PODclass?
  //var ownedRefNilCast      = borrowedRef5 : owned PODclass?;
  //writeln("ownedRefNilCast = ", ownedRefNilCast);
  //writeln("borrowedRef5 after cast = ", borrowedRef5);

  // casting borrowed to shared nilable
  //var borrowedRef6 = new borrowed PODclass("borrowedRef6", 104);
  //writeln("borrowedRef6 = ", borrowedRef6);
  // error: illegal cast from borrowed PODclass to shared PODclass?
  //var sharedRefNilCast     = borrowedRef6 : shared PODclass?;
  //writeln("sharedRefNilCast = ", sharedRefNilCast);
  //writeln("borrowedRef6 after cast = ", borrowedRef6);

  // casting borrowed to unmanaged nilable
  var borrowedRef7 = new borrowed PODclass("borrowedRef7", 105);
  writeln("borrowedRef7 = ", borrowedRef7);
  var unmanagedRefNilCast  = borrowedRef7 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  writeln("borrowedRef7 after cast = ", borrowedRef7);

  // casting borrowed to borrowed nilable
  var borrowedRef8 = new borrowed PODclass("borrowedRef8", 106);
  writeln("borrowedRef8 = ", borrowedRef8);
  var borrowedRefNilCast   = borrowedRef8 : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("borrowedRef8 after cast = ", borrowedRef8);
}

//=======================
//==== all of the above casting but now from nilable refs

{ // putting into a scope to avoid problem of not being able to transfer 
  // ownership from an outer variable

  var defaultRef1 = new PODclass?("defaultRef1", 107);
  writeln("defaultRef1 = ", defaultRef1);
  var ownedRefNonNilCast      = defaultRef1 : owned;
  writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  writeln("defaultRef1 after cast = ", defaultRef1);

  var sharedRefNonNilCast     = defaultRef1 : shared;

  var defaultRef2 = new PODclass?("defaultRef2", 108);
  writeln("defaultRef2 = ", defaultRef2);
  var unmanagedRefNonNilCast  = defaultRef2 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  // FIXME: should defaultRef2 lose ownership?
  writeln("defaultRef2 after cast = ", defaultRef2);

  var defaultRef3 = new PODclass?("defaultRef3", 109);
  writeln("defaultRef3 = ", defaultRef3);
  var borrowedRefNonNilCast   = defaultRef3 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("defaultRef3 after cast = ", defaultRef3);

  var defaultRef4 = new PODclass?("defaultRef4", 110);
  writeln("defaultRef4 = ", defaultRef4);
  var ownedRefNilCast         = defaultRef4 : owned PODclass?;
  writeln("ownedRefNilCast = ", ownedRefNilCast);
  writeln("defaultRef4 after cast = ", defaultRef4);

  var sharedRefNilCast        = defaultRef4 : shared PODclass?;

  var defaultRef5 = new PODclass?("defaultRef5", 111);
  writeln("defaultRef5 = ", defaultRef5);
  var unmanagedRefNilCast     = defaultRef5 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  writeln("defaultRef5 after cast = ", defaultRef5);

  var defaultRef6 = new PODclass?("defaultRef6", 112);
  writeln("defaultRef6 = ", defaultRef6);
  var borrowedRefNilCast      = defaultRef6 : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("defaultRef6 after cast = ", defaultRef6);
}
//==== casting a shared reference into variables
{ // putting in scope to reuse some var names

  // casting shared to own
  //var sharedRef1 = new shared PODclass?("sharedRef1", 113);
  //writeln("sharedRef1 = ", sharedRef1);
  // error: illegal cast from shared PODclass? to owned
  //var ownedRefNonNilCast      = sharedRef1 : owned;
  //writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  //writeln("sharedRef1 after cast = ", sharedRef1);

  // casting shared to shared
  var sharedRef2 = new shared PODclass?("sharedRef2", 114);
  writeln("sharedRef2 = ", sharedRef2);
  var sharedRefNonNilCast     = sharedRef2 : shared;
  writeln("sharedRefNonNilCast = ", sharedRefNonNilCast);
  writeln("sharedRef2 after cast = ", sharedRef2);

  var sharedRef3 = new shared PODclass?("sharedRef3", 115);
  writeln("sharedRef3 = ", sharedRef3);
  var unmanagedRefNonNilCast  = sharedRef3 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  writeln("sharedRef3 after cast = ", sharedRef3);

  var sharedRef4 = new shared PODclass?("sharedRef4", 116);
  writeln("sharedRef4 = ", sharedRef4);
  var borrowedRefNonNilCast   = sharedRef4 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("sharedRef4 after cast = ", sharedRef4);

  //var sharedRef5 = new shared PODclass?("sharedRef5", 117);
  //writeln("sharedRef5 = ", sharedRef5);
  // error: illegal cast from shared PODclass? to owned PODclass?
  //var ownedRefNilCast         = sharedRef5 : owned PODclass?;
  //writeln("ownedRefNilCast = ", ownedRefNilCast);
  //writeln("sharedRef5 after cast = ", sharedRef5);

  var sharedRef6 = new shared PODclass?("sharedRef6", 118);
  writeln("sharedRef6 = ", sharedRef6);
  var sharedRefNilCast        = sharedRef6 : shared PODclass?;
  writeln("sharedRefNilCast = ", sharedRefNilCast);
  writeln("sharedRef6 after cast = ", sharedRef6);

  var sharedRef7 = new shared PODclass?("sharedRef7", 119);
  writeln("sharedRef7 = ", sharedRef7);
  var unmanagedRefNilCast     = sharedRef7 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  writeln("sharedRef7 after cast = ", sharedRef7);

  var sharedRef8 = new shared PODclass?("sharedRef8", 120);
  writeln("sharedRef8 = ", sharedRef8);
  var borrowedRefNilCast      = sharedRef8 : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("sharedRef8 after cast = ", sharedRef8);
}
//==== casting an unmanaged reference into variables
{ // putting in scope to reuse some var names

  // casting unmanaged to owned
  //var unmanagedRef1 = new unmanaged PODclass?("unmanagedRef1", 121);
  //writeln("unmanagedRef1 = ", unmanagedRef1);
  // error: illegal cast from unmanaged PODclass? to owned
  //var ownedRefNonNilCast      = unmanagedRef1 : owned;
  //writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  //writeln("unmanagedRef1 after cast = ", unmanagedRef1);

  // casting unmanaged to shared
  //var unmanagedRef2 = new unmanaged PODclass?("unmanagedRef2", 122);
  //writeln("unmanagedRef2 = ", unmanagedRef2);
  // error: illegal cast from unmanaged PODclass? to shared
  //var sharedRefNonNilCast     = unmanagedRef2 : shared;
  //writeln("sharedRefNonNilCast = ", sharedRefNonNilCast);
  //writeln("unmanagedRef2 after cast = ", unmanagedRef2);

  // casting unmanaged to unmanaged
  var unmanagedRef3 = new unmanaged PODclass?("unmanagedRef3", 123);
  writeln("unmanagedRef3 = ", unmanagedRef3);
  var unmanagedRefNonNilCast  = unmanagedRef3 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  writeln("unmanagedRef3 after cast = ", unmanagedRef3);

  // casting unmanaged to borrowed
  var unmanagedRef4 = new unmanaged PODclass?("unmanagedRef4", 124);
  writeln("unmanagedRef4 = ", unmanagedRef4);
  var borrowedRefNonNilCast   = unmanagedRef4 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("unmanagedRef4 after cast = ", unmanagedRef4);

  // casting unmanaged to owned nilable
  //var unmanagedRef5 = new unmanaged PODclass?("unmanagedRef5", 125);
  //writeln("unmanagedRef5 = ", unmanagedRef5);
  // error: illegal cast from unmanaged PODclass? to owned PODclass?
  //var ownedRefNilCast         = unmanagedRef5 : owned PODclass?;
  //writeln("ownedRefNilCast = ", ownedRefNilCast);
  //writeln("unmanagedRef5 after cast = ", unmanagedRef5);

  // casting unmanaged to shared nilable
  //var unmanagedRef6 = new unmanaged PODclass?("unmanagedRef6", 126);
  //writeln("unmanagedRef6 = ", unmanagedRef6);
  // error: illegal cast from unmanaged PODclass to shared PODclass?
  //var sharedRefNilCast        = unmanagedRef : shared PODclass?;
  //writeln("sharedRefNilCast = ", sharedRefNilCast);
  //writeln("unmanagedRef6 after cast = ", unmanagedRef6);

  // casting unmanaged to unmanaged nilable
  var unmanagedRef7 = new unmanaged PODclass?("unmanagedRef7", 127);
  writeln("unmanagedRef7 = ", unmanagedRef);
  var unmanagedRefNilCast     = unmanagedRef7 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  writeln("unmanagedRef7 after cast = ", unmanagedRef7);

  // casting unmanaged to borrowed nilable
  var unmanagedRef8 = new unmanaged PODclass?("unmanagedRef8", 128);
  writeln("unmanagedRef8 = ", unmanagedRef8);
  var borrowedRefNilCast      = unmanagedRef : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("unmanagedRef8 after cast = ", unmanagedRef8);
}

//==== casting a borrowed reference into variables
{ // putting in scope to reuse some var names

  // casting borrowed to owned
  //var borrowedRef1 = new borrowed PODclass?("borrowedRef1", 129);
  //writeln("borrowedRef1 = ", borrowedRef1);
  // error: illegal cast from borrowed PODclass? to owned
  //var ownedRefNonNilCast      = borrowedRef1 : owned;
  //writeln("ownedRefNonNilCast = ", ownedRefNonNilCast);
  //writeln("borrowedRef1 after cast = ", borrowedRef1);

  // casting borrowed to shared
  //var borrowedRef2 = new borrowed PODclass?("borrowedRef2", 130);
  //writeln("borrowedRef2 = ", borrowedRef2);
  // error: illegal cast from borrowed PODclass? to shared
  //var sharedRefNonNilCast     = borrowedRef2 : shared;
  //writeln("sharedRefNonNilCast = ", sharedRefNonNilCast);
  //writeln("borrowedRef2 after cast = ", borrowedRef2);

  // casting borrowed to unmanaged
  var borrowedRef3 = new borrowed PODclass?("borrowedRef3", 131);
  writeln("borrowedRef3 = ", borrowedRef3);
  var unmanagedRefNonNilCast  = borrowedRef3 : unmanaged;
  writeln("unmanagedRefNonNilCast = ", unmanagedRefNonNilCast);
  writeln("borrowedRef3 after cast = ", borrowedRef3);

  // casting borrowed to borrowed
  var borrowedRef4 = new borrowed PODclass?("borrowedRef4", 132);
  writeln("borrowedRef4 = ", borrowedRef4);
  var borrowedRefNonNilCast   = borrowedRef4 : borrowed;
  writeln("borrowedRefNonNilCast = ", borrowedRefNonNilCast);
  writeln("borrowedRef4 after cast = ", borrowedRef4);

  // casting borrowed to owned nilable
  //var borrowedRef5 = new borrowed PODclass?("borrowedRef5", 133);
  //writeln("borrowedRef5 = ", borrowedRef5);
  // error: illegal cast from borrowed PODclass? to owned PODclass?
  //var ownedRefNilCast      = borrowedRef5 : owned PODclass?;
  //writeln("ownedRefNilCast = ", ownedRefNilCast);
  //writeln("borrowedRef5 after cast = ", borrowedRef5);

  // casting borrowed to shared nilable
  //var borrowedRef6 = new borrowed PODclass?("borrowedRef6", 134);
  //writeln("borrowedRef6 = ", borrowedRef6);
  // 939: error: illegal cast from borrowed PODclass? to shared PODclass?
  //var sharedRefNilCast     = borrowedRef6 : shared PODclass?;
  //writeln("sharedRefNilCast = ", sharedRefNilCast);
  //writeln("borrowedRef6 after cast = ", borrowedRef6);

  // casting borrowed to unmanaged nilable
  var borrowedRef7 = new borrowed PODclass?("borrowedRef7", 135);
  writeln("borrowedRef7 = ", borrowedRef7);
  var unmanagedRefNilCast  = borrowedRef7 : unmanaged PODclass?;
  writeln("unmanagedRefNilCast = ", unmanagedRefNilCast);
  writeln("borrowedRef7 after cast = ", borrowedRef7);

  // casting borrowed to borrowed nilable
  var borrowedRef8 = new borrowed PODclass?("borrowedRef8", 136);
  writeln("borrowedRef8 = ", borrowedRef8);
  var borrowedRefNilCast   = borrowedRef8 : borrowed PODclass?;
  writeln("borrowedRefNilCast = ", borrowedRefNilCast);
  writeln("borrowedRef8 after cast = ", borrowedRef8);
}

//==== What kind of reference can be coerced to what other kind of reference.
// Non-nilable class types are implicitly convertible to nilable class types. 
// https://chapel-lang.org/docs/main/language/spec/conversions.html#implicit-class-conversions

proc f1(arg: owned PODclass) { writeln("owned arg=", arg); }
proc f2(arg: shared PODclass) { writeln("shared arg=", arg); }
proc f3(arg: unmanaged PODclass) { writeln("unmanaged arg=", arg); }
proc f4(arg: borrowed PODclass) { writeln("borrowed arg=", arg); }

proc f5(arg: owned PODclass?) { writeln("ownednil arg=", arg); }
proc f6(arg: shared PODclass?) { writeln("sharednil arg=", arg); }
proc f7(arg: unmanaged PODclass?) { writeln("unmanagednil arg=", arg); }
proc f8(arg: borrowed PODclass?) { writeln("borrowednil arg=", arg); }

// based on documentation "class types can be converted to the 
// corresponding borrowed type"
f4(new owned PODclass("newOwnedExpr", 137));
f8(new owned PODclass?("newOwnedNilExpr", 138));
f4(new shared PODclass("newSharedExpr", 139));
f8(new shared PODclass?("newSharedNilExpr", 140));

// In assignments could assign an owned ref to a shared, coercions too?
// Ok docs are consistent.
// error: unresolved call 'f6(owned PODclass)'
// note: this candidate did not match: f6(arg: shared PODclass?)
// note: because actual argument #1 with type 'owned PODclass'
// note: is passed to formal 'arg: shared PODclass?'
//f6(new owned PODclass("newOwnedExpr", 103));

// just checking that can't coerce to or from an unmanaged
// error: unresolved call 'f1(unmanaged PODclass)'
// .. similar notes to above
//f1(new unmanaged PODclass("newUnmanagedExpr", 103));
// error: unresolved call 'f7(owned PODclass?)'
//f7(new owned PODclass?("newOwnedNilExpr", 104));


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

