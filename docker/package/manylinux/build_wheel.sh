#!/usr/bin/env bash

set -x
set -e

export LD_LIBRARY_PATH=/opt/intel/lib/intel64_lin:/opt/intel/mkl/lib/intel64:$LD_LIBRARY_PATH

EXTRA_ONEFLOW_CMAKE_ARGS=""
PY_VERS=()

while [[ "$#" > 0 ]]; do
    case $1 in
        --skip-third-party) SKIP_THIRD_PARTY=1; ;;
        --cache-dir) CACHE_DIR=$2; shift ;;
        --house-dir) HOUSE_DIR=$2; shift ;;
        --python3.5) PY_VERS+=( "35" ) ;;
        --python3.6) PY_VERS+=( "36" ) ;;
        --python3.7) PY_VERS+=( "37" ) ;;
        --python3.8) PY_VERS+=( "38" ) ;;
        *) EXTRA_ONEFLOW_CMAKE_ARGS="${EXTRA_ONEFLOW_CMAKE_ARGS} $1" ;;
    esac;
    shift;
done

if [[ ! -v CACHE_DIR ]]
then
    CACHE_DIR=$PWD/manylinux2014-build-cache
fi

if [[ ! -v HOUSE_DIR ]]
then
    HOUSE_DIR=$PWD/wheelhouse
fi

ONEFLOW_SRC_DIR=`cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd`
ONEFLOW_SRC_DIR=$ONEFLOW_SRC_DIR/../../..

if [[ ${#PY_VERS[@]} -eq 0 ]]
then
    PY_VERS=( 35 36 37 38 )
fi

cd $ONEFLOW_SRC_DIR

THIRD_PARTY_BUILD_DIR=$CACHE_DIR/build-third-party
THIRD_PARTY_INSTALL_DIR=$CACHE_DIR/build-third-party-install
if [[ $SKIP_THIRD_PARTY != 1 ]]; then
    mkdir -p $THIRD_PARTY_BUILD_DIR
    pushd $THIRD_PARTY_BUILD_DIR

    cmake -DTHIRD_PARTY=ON -DCMAKE_BUILD_TYPE=Release \
        -DONEFLOW=OFF \
        -DTHIRD_PARTY_DIR=$THIRD_PARTY_INSTALL_DIR   \
        -DBUILD_RDMA=ON \
        $ONEFLOW_SRC_DIR
    make -j nccl
    make -j`nproc` prepare_oneflow_third_party

    popd
fi

ONEFLOW_BUILD_DIR=$CACHE_DIR/build-oneflow

function cleanup {
  set -x
  rm  -r tmp_wheel
}

for PY_VER in ${PY_VERS[@]}
do
    mkdir -p $ONEFLOW_BUILD_DIR
    pushd $ONEFLOW_BUILD_DIR
    PY_ABI=cp${PY_VER}-cp${PY_VER}
    if [[ $PY_VER != 38 ]]
    then
        PY_ABI=${PY_ABI}m
    fi
    PY_ROOT=/opt/python/${PY_ABI}
    PY_BIN=${PY_ROOT}/bin/python
    cmake -DTHIRD_PARTY=OFF -DONEFLOW=ON\
        -DPython3_ROOT_DIR=$PY_ROOT \
        -DCMAKE_BUILD_TYPE=Release  \
        -DTHIRD_PARTY_DIR=$THIRD_PARTY_INSTALL_DIR   \
        -DBUILD_RDMA=ON \
        $EXTRA_ONEFLOW_CMAKE_ARGS   \
        $ONEFLOW_SRC_DIR
    cmake --build . -j `nproc`
    popd
    trap cleanup EXIT
    $PY_BIN setup.py bdist_wheel -d tmp_wheel --build_dir $ONEFLOW_BUILD_DIR
    auditwheel repair tmp_wheel/*.whl --wheel-dir $HOUSE_DIR
done
