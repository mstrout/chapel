use CyclicDist;
use BlockDist;

use Time;
use PrintComms;
config const doDiagnostics=false;
config const printOutput=true;
config const printComm=false;

config  const n: int=10;

const Space2 = {1..n,1..n};
const Dom2: domain(2) dmapped Cyclic(startIdx=Space2.low)=Space2;
const Space3 = {1..n,1..n,1..n};
const Dom3: domain(3) dmapped Cyclic(startIdx=Space3.low)=Space3;

var Dist2 = new blockDist({1..n,1..n});
var Dom2B: domain(2,int) dmapped Dist2 = {1..n,1..n};
var Dist3 = new blockDist({1..n,1..n,1..n});
var Dom3B: domain(3,int) dmapped Dist3 = {1..n,1..n,1..n};


var A2:[Dom2] real;
var A3:[Dom3] real;
var BD:[Dom2B] real;
var BD3:[Dom3B] real;

proc main(){

  var a,b:real;
  var i:int;
  var D1={1..n, 1..n}: domain(2, strides=strideKind.positive);
  var D2={1..n, 1..n}: domain(2, strides=strideKind.positive);
  var D3={1..n, 1..n, 1..n}: domain(3, strides=strideKind.positive);
  var D4={1..n, 1..n, 1..n}: domain(3, strides=strideKind.positive);
  
  var st,dt=timeSinceEpoch().totalSeconds();
  for (a,i) in zip(A2,{1..n*n}) do a=i;
//2D Examples
// ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D2 ={1..10 by 1,1..10 by 1};
  D1={1..10 by 1 ,1..10 by 1};
  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 1:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D2 ={1..n/2 by 2,1..n};
  D1={1..n by 4 ,1..n};
  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 2:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
 
 // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D2 ={1..n,1..n/2 by 2};
  D1={1..n,1..n by 4};
if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 3:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
 
 // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D2 ={2..n/2 +1,1..n/2 -1};
  D1={n/2+1..n,n/2+2..n};
if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 4:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
 
  
  // ==============================================================================
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D2 ={3..n-2 by 2,1..n/2 by 2};
  D1={4..n-1 by 2,1..n by 4};
if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 5:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  // ==============================================================================
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D1 ={2..n-1 by 2,1..n/2 by 2};
  D2={3..n by 2,1..n by 4};
if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 6:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
   // ==============================================================================
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D1 ={1..n by 2,2..(n-1)/2};
  D2={1..n by 2,3..n-2 by 2};
if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 7:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
  // ==============================================================================
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D2 ={2..n-1 by 2,3..n/2};
  D1={3..n by 2,4..n-1 by 2};
  //D2 ={6..8 by 2,3..n/2};
  //D1={7..9 by 2,4..n-1 by 2};
if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 8:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }
  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
   // ==============================================================================
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D1 ={2..n/2,2..n/2};
  D2={2..n-1 by 2 ,2..n/2};
if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 9:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
  // ==============================================================================
  //Reset array A
  for (a,i) in zip(A2,{1..n*n}) do a=i;
  for (a,i) in zip(BD,{1..n*n}) do a=i+100;
  D2 ={5..n/2,2..(n/2)-1};
  D1={7..n-2 by 2 ,3..n/2};
  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 10:CY",D1," = BD",D2);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A2[D1]=BD[D2];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A2[D1],BD[D2]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
  //3D Examples
// ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D3 ={2..10 by 1,2..9 by 1,7..10};
  D4={1..9 by 1 ,3..10 by 1,3..6};
  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 11:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}

// ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D3 ={1..n/2 by 2,1..n,3..n/2+2};
  D4={1..n by 4 ,1..n,1..n/2};
  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 12:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D4 ={1..n/2 by 2,2..n-1,3..n/2+3};
  D3={1..n by 4 ,3..n,2..n/2+2};

  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 13:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D4 ={2..n by 2,3..n/2 by 2,1..n/4};
  D3={1..n-1 by 2,5..n by 4,1..n/4};
  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 14:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D3 ={6..n-1 by 2,1..n/2 by 2,5..n/4-2};
  D4={7..n by 2,1..n by 4,7..n/4};

  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 15:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}

  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D3 ={1..n-1 by 2,1..n/2 by 2,3..n-2 by 2};
  D4={2..n by 2,1..n by 4,5..n by 2};

  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 16:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
    D4 ={1..n by 2,1..n/2 by 2,1..n by 2};
  D3={1..n by 2,1..n by 4,1..n by 2};

  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 17:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  
  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D4 ={1..n by 2,1..n/2,1..n/2};
  D3={1..n by 2,1..n by 2,1..n by 2};

  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 18:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}
  // ==============================================================================
 
  //Reset array A
  for (a,i) in zip(A3,{1..n*n*n}) do a=i;
  for (a,i) in zip(BD3,{1..n*n*n}) do a=i+100;
  D3 ={1..n by 2,1..n/2,1..n/2};
  D4={1..n by 2,1..n by 2,1..n by 2};
  
  if printOutput then writeln(" Cyclic Dist <-- Block Dist. Example 19:CY",D3," = BD",D4);
  if doDiagnostics {
    if printComm{
      resetCommDiagnostics();
      startCommDiagnostics();
    }
  }
  st = timeSinceEpoch().totalSeconds();
  A3[D3]=BD3[D4];
  dt = timeSinceEpoch().totalSeconds()-st;
  if doDiagnostics {
    if printComm{
      stopCommDiagnostics();
      myPrintComms("");
    }
    writeln("Time: ", dt);
  }

  for (a,b) in zip(A3[D3],BD3[D4]) do if (a!=b){ writeln("ERROR!!!!"); break;}
 
}