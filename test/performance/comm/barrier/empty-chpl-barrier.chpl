use Time;
use Barriers;
use AllLocalesBarriers;

config const numTrials = 100;
config const printTimings = false;

config const numTasksPerLocale = here.maxTaskPar;
const numTasks = numLocales * numTasksPerLocale;

enum BarrierMode {
  LocalAtomic,
  GlobalAllLocales
};
use BarrierMode;

config param barrierMode = LocalAtomic;

proc main() {
  var t: stopwatch;

  t.start();
  select barrierMode {
    when LocalAtomic do LocalBarrierBarrier();
    when GlobalAllLocales do GlobalAllLocalesBarrierBarrier();
  }
  t.stop();

  if printTimings {
    writeln("Elapsed time: ", t.elapsed());
  }
}

proc LocalBarrierBarrier() {
  var barrier = new Barrier(numTasks);
  coforall loc in Locales do on loc do
    coforall 1..numTasksPerLocale do
      for 1..numTrials do
        barrier.barrier();
}

proc GlobalAllLocalesBarrierBarrier() {
  allLocalesBarrier.reset(numTasksPerLocale);
  coforall loc in Locales do on loc do
    coforall 1..numTasksPerLocale do
      for 1..numTrials do
        allLocalesBarrier.barrier();
}
