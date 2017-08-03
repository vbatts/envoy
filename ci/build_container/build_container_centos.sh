#!/bin/bash

set -e

# Setup basic requirements and install them.
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install -y wget make git java-1.8.0-openjdk-devel bc libtool zip unzip \
    gdb strace python2-pip which golang centos-release-scl
yum install -y devtoolset-4-gcc-c++ # to get gcc-c++-5.3. Closer to the 5.4 they're expecting, than stock 4.8.5
# XXX to use this gcc, prefix commands with `scl enable devtoolset-4 -- ...`

# bazel build
BAZEL_VERSION="0.5.3"
wget https://github.com/bazelbuild/bazel/releases/download/"${BAZEL_VERSION}"/bazel-"${BAZEL_VERSION}"-without-jdk-installer-linux-x86_64.sh
bash ./bazel-"${BAZEL_VERSION}"-without-jdk-installer-linux-x86_64.sh
rm -f ./bazel-"${BAZEL_VERSION}"-without-jdk-installer-linux-x86_64.sh

# TODO(vbatts) they need clang 5.0'ish, which is not packaged but for ubuntu:xenial...
# compile it from source? ...
yum install -y subversion
yum-builddep -y llvm clang

CMAKE_VERSION="3.4.3"
wget https://cmake.org/files/v3.4/cmake-"${CMAKE_VERSION}"-Linux-x86_64.sh
yes y | sh cmake-"${CMAKE_VERSION}"-Linux-x86_64.sh
rsync -avPHS ./cmake-"${CMAKE_VERSION}"-Linux-x86_64/ /usr/local/
rm -f cmake-"${CMAKE_VERSION}"-Linux-x86_64.sh

# yaaay ... compile llvm/clang 5.0.0-rc1 ...
svn co http://llvm.org/svn/llvm-project/llvm/tags/RELEASE_500/rc1/ llvm
pushd llvm/tools
svn co http://llvm.org/svn/llvm-project/cfe/tags/RELEASE_500/rc1/ clang
cd clang/tools
svn co http://llvm.org/svn/llvm-project/clang-tools-extra/tags/RELEASE_500/rc1/ extra
cd ../../../projects
svn co http://llvm.org/svn/llvm-project/compiler-rt/tags/RELEASE_500/rc1/ compiler-rt
cd ../..
mkdir -p llvm.build
cd llvm.build
scl enable devtoolset-4 -- cmake -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    ../llvm
numjobs=$(lscpu | grep '^CPU(s):' | awk '{ print $2 }')
if [ "x${numjobs}" = "x" ] ; then
    numjobs=1
fi
make -j"${numjobs}"
make install
popd

#rm -rf llvm llvm.build
#yum remove -y subversion
#yum clean all

# virtualenv
pip install virtualenv

# buildifier
export GOPATH=/usr/lib/go
go get github.com/bazelbuild/buildifier/buildifier

# GCC for everything.
export CC="scl enable devtoolset-4 -- gcc"
export CXX="scl enable devtoolset-4 -- g++"
CXX_VERSION="$(${CXX} --version | grep ^g++)"
if [[ "${CXX_VERSION}" != "g++ (GCC) 5.3.1 20160406 (Red Hat 5.3.1-6)" ]]; then
  echo "Unexpected compiler version: ${CXX_VERSION}"
  exit 1
fi
