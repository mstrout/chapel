#!/usr/bin/env bash
#
# Configure environment for CHAMPS testing

CWD=$(cd $(dirname ${BASH_SOURCE[0]}) ; pwd)

COMMON_DIR=/cy/users/chapelu

export CHAMPS_COMMON_DIR=$COMMON_DIR/champs-nightly

pushd $CHAMPS_COMMON_DIR
git pull
popd

source $CRAY_ENABLE_PE

# All CHAMPS testing is currently on a hpe-apollo
module list

source $CWD/common-hpe-apollo.bash
source $CWD/common-perf-hpe-apollo-hdr.bash

module load PrgEnv-gnu
module load cray-pmi
module load cray-mpich
module load cray-hdf5-parallel

module list

# Perf configuration
source $CWD/common-perf.bash
CHAMPS_PERF_DIR=${CHAMPS_PERF_DIR:-$COMMON_DIR/NightlyPerformance/champs}
export CHPL_TEST_PERF_DIR=$CHAMPS_PERF_DIR/$CHPL_TEST_PERF_CONFIG_NAME
export CHPL_TEST_PERF_START_DATE=01/21/22

# Run champs correctness and performance testing
export CHPL_NIGHTLY_TEST_DIRS=studies/champs/
export CHPL_TEST_CHAMPS=true

# Intel installation is hard for me to understand, I had to wire things
# manually.
export MKLROOT=/sw/sdev/intel/oneapi/2023/v2/mkl/2023.2.0/
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$MKLROOT/lib/intel64

# Note that this is used for libiomp. The path for this and MKL are different
# Also, INTELROOT is not a "standard" CHAMPS Makefile flag. Our patch adds it.
export INTELROOT=/sw/sdev/intel/oneapi/2023/v2/compiler/2023.2.0/linux/compiler
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$INTELROOT/lib/intel64

export MPIROOT=$(dirname $(dirname $(which mpicc)))
export HDF5ROOT=$(dirname $(dirname $(which h5pcc)))

CHAMPS_DEP_DIR=$CHAMPS_COMMON_DIR/deps-manual
if [ -d "$CHAMPS_DEP_DIR" ]; then
  export METISROOT=${METISROOT:-$CHAMPS_DEP_DIR}
  export CGNSROOT=${CGNSROOT:-$CHAMPS_DEP_DIR}
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CHAMPS_DEP_DIR/lib
fi

export CPATH=$CPATH:$MPIROOT/include

export CHPL_TARGET_CPU=none

# these may be unnecessary
export GASNET_PHYSMEM_MAX="9/10"
export GASNET_IBV_SPAWNER=ssh

export CHPL_TEST_PERF_CONFIGS="llvm:v,c-backend"  # v: visible by def

function sync_graphs() {
  $CHPL_HOME/util/cron/syncPerfGraphs.py $CHPL_TEST_PERF_DIR/html/ champs/$CHPL_TEST_PERF_CONFIG_NAME
}
