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
// reference types.  It also explores the space of default coercions, casts,
// and assignments to and from various memory management reference types that
// Chapel currently has with some discussion of what we might potentially want
// to modify for the Chapel 2.0 effort.

// OUTLINE: The default initializations for the different class reference types.

// OUTLINE: Where does nilable and non-nilable come into play?

// OUTLINE: What kind of reference can be assigned to what other kind of reference.

// OUTLINE: What kind of reference can be cast to what other kind of reference.

// OUTLINE: What kind of reference can be coerced to what other kind of reference.


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

