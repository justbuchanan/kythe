// Checks that forward declarations are referenced correctly.

//- @FwdClass defines/binding FwdDecl
//- FwdDecl.node/kind record
//- FwdDecl.complete incomplete
class FwdClass;

//- @Box defines/binding BoxClass
class Box {
  //- @cfwd defines/binding CFwdDecl
  //- CFwdDecl childof BoxClass
  //- @FwdClass ref vname("FwdClass#c#t",_,_,_,_)
  FwdClass *cfwd;
};
