#! /bin/bash

TENSORFLOW_VERSION=v2.9.1


MANIFEST_TFLITE_BUILDER=tflite-builder:${TENSORFLOW_VERSION}
MANIFEST_TFLITE_RUNTIME=tflite-runtime:${TENSORFLOW_VERSION}
OCI_REGISTRY=docker.io/cyrilix
BASE_IMAGE=docker.io/library/debian:stable-slim

CONTAINER_TFLITE=tensorflow-build
CONTAINER_RUNTIME=tflite-runtime
CONTAINER_BUILDER=tflite-builder

build_tensorflow_lite(){

  local containerName=$CONTAINER_TFLITE

  buildah --name=$containerName --os=linux --arch=amd64 from $BASE_IMAGE

  buildah run $containerName mkdir -p /src/toolchains/

  buildah run $containerName apt-get update
  buildah run $containerName apt-get install -y \
                                  git \
                                  cmake \
                                  curl \
                                  build-essential

  buildah config --workingdir=/src $containerName

  buildah run $containerName git clone https://github.com/tensorflow/tensorflow.git
  buildah config --workingdir=/src/tensorflow $containerName
  buildah run $containerName git checkout ${TENSORFLOW_VERSION}

  printf "Build amd64\n"
  buildah run $containerName mkdir -p /src/build/amd64
  buildah config --workingdir=/src/build/amd64 $containerName

  buildah run $containerName cmake \
                  -DBUILD_SHARED_LIBS=ON \
                  -DTFLITE_ENABLE_RUY=ON \
                  -DTFLITE_ENABLE_XNNPACK=ON \
                  -DTFLITE_ENABLE_NNAPI=ON \
                  -DTFLITE_ENABLE_GPU=ON \
                  -DTFLITE_ENABLE_MMAP=ON \
                  ../../tensorflow/tensorflow/lite
  buildah run $containerName cmake --build . -j 14

  printf "Build armhf\n"

  buildah config --workingdir=/src/toolchains/ $containerName
  buildah run $containerName curl -LO https://storage.googleapis.com/mirror.tensorflow.org/developer.arm.com/media/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz
  buildah run $containerName tar xvf gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz -C /src/toolchains

  buildah run $containerName mkdir -p /src/build/armhf

  buildah config --workingdir=/src/build/armhf $containerName
  CC_FLAGS="-march=armv7-a -mfpu=neon-vfpv4 -funsafe-math-optimizations"
  ARMCC_PREFIX=/src/toolchains/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf/bin/arm-linux-gnueabihf-

  buildah run $containerName cmake \
                  -DBUILD_SHARED_LIBS=ON \
                  -DTFLITE_ENABLE_RUY=ON \
                  -DTFLITE_ENABLE_XNNPACK=ON \
                  -DTFLITE_ENABLE_NNAPI=ON \
                  -DTFLITE_ENABLE_GPU=ON \
                  -DTFLITE_ENABLE_MMAP=ON \
                  -DCMAKE_C_COMPILER=${ARMCC_PREFIX}gcc \
                  -DCMAKE_CXX_COMPILER=${ARMCC_PREFIX}g++ \
                  -DCMAKE_C_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_CXX_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
                  -DCMAKE_SYSTEM_NAME=Linux \
                  -DCMAKE_SYSTEM_PROCESSOR=armv7 \
                  ../../tensorflow/tensorflow/lite
  buildah run $containerName cmake --build . -j 14


  printf "Build arm64\n"

  buildah config --workingdir=/src/toolchains/ $containerName
  buildah run $containerName curl -LO https://storage.googleapis.com/mirror.tensorflow.org/developer.arm.com/media/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz
  buildah run $containerName tar xvf gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz -C /src/toolchains

  buildah run $containerName mkdir -p /src/build/arm64

  buildah config --workingdir=/src/build/arm64 $containerName
  CC_FLAGS="-funsafe-math-optimizations"
  ARMCC_PREFIX=/src/toolchains/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu/bin/aarch64-linux-gnu-

  buildah run $containerName cmake \
                  -DBUILD_SHARED_LIBS=ON \
                  -DTFLITE_ENABLE_RUY=ON \
                  -DTFLITE_ENABLE_XNNPACK=ON \
                  -DTFLITE_ENABLE_NNAPI=ON \
                  -DTFLITE_ENABLE_GPU=ON \
                  -DTFLITE_ENABLE_MMAP=ON \
                  -DCMAKE_C_COMPILER=${ARMCC_PREFIX}gcc \
                  -DCMAKE_CXX_COMPILER=${ARMCC_PREFIX}g++ \
                  -DCMAKE_C_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_CXX_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
                  -DCMAKE_SYSTEM_NAME=Linux \
                  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
                  ../../tensorflow/tensorflow/lite
  buildah run $containerName cmake --build . -j 14
}

build_tflite_runtime(){

  local platform=$1
  local containerName=$CONTAINER_RUNTIME



  OS=$(echo "$platform" | cut -f1 -d/) && \
  ARCH=$(echo "$platform" | cut -f2 -d/) && \
  ARM=$(echo "$platform" | cut -f3 -d/ | sed "s/v//" )
  VARIANT="--variant $(echo "${platform}" | cut -f3 -d/  )"
  if [[ -z "$ARM" ]] ;
  then
    VARIANT=""
  fi

  if [[ "${ARCH}" == "arm" ]]
  then
    BINARY_ARCH="armhf"
  else
    BINARY_ARCH="${ARCH}"
  fi


  buildah --name "$containerName" --os "${OS}" --arch "${ARCH}" ${VARIANT} from $BASE_IMAGE

  buildah run $containerName apt-get update
  buildah run $containerName apt-get install -y \
                      ca-certificates \
                      curl

  buildah run $containerName \
        /bin/bash -c "curl https://packages.cloud.google.com/apt/doc/apt-key.gpg > /etc/apt/trusted.gpg.d/google.gpg"
  buildah run $containerName \
        /bin/bash -c "echo \"deb https://packages.cloud.google.com/apt coral-edgetpu-stable main\" | tee /etc/apt/sources.list.d/coral-edgetpu.list"

  buildah run $containerName apt-get update
  buildah run $containerName apt-get install -y \
                      libedgetpu1-std

  buildah run $containerName mkdir -p \
                                  /usr/local/lib/absl/base \
                                  /usr/local/lib/absl/debugging \
                                  /usr/local/lib/absl/container \
                                  /usr/local/lib/absl/flags \
                                  /usr/local/lib/absl/hash \
                                  /usr/local/lib/absl/numeric \
                                  /usr/local/lib/absl/profiling \
                                  /usr/local/lib/absl/status \
                                  /usr/local/lib/absl/strings \
                                  /usr/local/lib/absl/synchronization \
                                  /usr/local/lib/absl/time \
                                  /usr/local/lib/absl/types

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/libtensorflow-lite.so /usr/local/lib/libtensorflowlite_c.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/fft2d-build/libfft2d_fftsg.so /usr/local/lib/libfft2d_fftsg.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/fft2d-build/libfft2d_fftsg2d.so /usr/local/lib/libfft2d_fftsg2d.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/xnnpack-build/libXNNPACK.so /usr/local/lib/libXNNPACK.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/cpuinfo-build/libcpuinfo.so /usr/local/lib/libcpuinfo.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/farmhash-build/libfarmhash.so /usr/local/lib/libfarmhash.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/base/*.so /usr/local/lib/absl/base
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/debugging/*.so /usr/local/lib/absl/debugging
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/container/*.so /usr/local/lib/absl/container
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/flags/*.so /usr/local/lib/absl/flags
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/hash/*.so /usr/local/lib/absl/hash
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/numeric/*.so /usr/local/lib/absl/numeric
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/profiling/*.so /usr/local/lib/absl/profiling
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/status/*.so /usr/local/lib/absl/status
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/strings/*.so /usr/local/lib/absl/strings
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/synchronization/*.so /usr/local/lib/absl/synchronization
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/time/*.so /usr/local/lib/absl/time
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/_deps/abseil-cpp-build/absl/types/*.so /usr/local/lib/absl/types
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/pthreadpool/libpthreadpool.so /usr/local/lib/

  buildah commit --rm --manifest "${MANIFEST_TFLITE_RUNTIME}" "${containerName}"
}

build_tflite_builder(){

  local containerName=$CONTAINER_BUILDER

  buildah --name "$containerName" --os="linux" --arch="amd64" ${VARIANT} from $BASE_IMAGE

  buildah run "$containerName" dpkg --add-architecture arm64
  buildah run "$containerName" dpkg --add-architecture armhf

  buildah run $containerName apt-get update
  buildah run $containerName apt-get install -y \
                      git \
                      cmake \
                      curl \
                      ca-certificates \
                      build-essential \
                      crossbuild-essential-arm64 \
                      crossbuild-essential-armhf

  buildah run $containerName \
          /bin/bash -c "curl https://packages.cloud.google.com/apt/doc/apt-key.gpg > /etc/apt/trusted.gpg.d/google.gpg"
  buildah run $containerName \
          /bin/bash -c "echo \"deb https://packages.cloud.google.com/apt coral-edgetpu-stable main\" | tee /etc/apt/sources.list.d/coral-edgetpu.list"
  buildah run $containerName apt-get update
  buildah run $containerName apt-get install -y \
                      libedgetpu-dev

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/tensorflow/tensorflow/lite/c/c_api.h /usr/local/include/tensorflow/lite/c/c_api.h
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/tensorflow/tensorflow/lite/c/c_api_experimental.h /usr/local/include/tensorflow/lite/c/c_api_experimental.h
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/tensorflow/tensorflow/lite/c/c_api_types.h /usr/local/include/tensorflow/lite/c/c_api_types.h
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/tensorflow/tensorflow/lite/c/common.h /usr/local/include/tensorflow/lite/c/common.h
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/tensorflow/tensorflow/lite/builtin_ops.h /usr/local/include/tensorflow/lite/builtin_ops.h



  buildah run $containerName apt-get install -y \
                  libedgetpu1-std:amd64\
                  libedgetpu1-std:arm64\
                  libedgetpu1-std:armhf

  printf "Copy amd64 lib\n"
  buildah run $containerName mkdir -p \
                                  /usr/local/lib/x86_64-linux-gnu \
                                  /usr/local/lib/x86_64-linux-gnu/absl/base \
                                  /usr/local/lib/x86_64-linux-gnu/absl/debugging \
                                  /usr/local/lib/x86_64-linux-gnu/absl/container \
                                  /usr/local/lib/x86_64-linux-gnu/absl/flags \
                                  /usr/local/lib/x86_64-linux-gnu/absl/hash \
                                  /usr/local/lib/x86_64-linux-gnu/absl/numeric \
                                  /usr/local/lib/x86_64-linux-gnu/absl/profiling \
                                  /usr/local/lib/x86_64-linux-gnu/absl/status \
                                  /usr/local/lib/x86_64-linux-gnu/absl/strings \
                                  /usr/local/lib/x86_64-linux-gnu/absl/synchronization \
                                  /usr/local/lib/x86_64-linux-gnu/absl/time \
                                  /usr/local/lib/x86_64-linux-gnu/absl/types

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/libtensorflow-lite.so /usr/local/lib/x86_64-linux-gnu/libtensorflowlite_c.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/fft2d-build/libfft2d_fftsg.so /usr/local/lib/x86_64-linux-gnu/libfft2d_fftsg.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/fft2d-build/libfft2d_fftsg2d.so /usr/local/lib/x86_64-linux-gnu/libfft2d_fftsg2d.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/xnnpack-build/libXNNPACK.so /usr/local/lib/x86_64-linux-gnu/libXNNPACK.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/cpuinfo-build/libcpuinfo.so /usr/local/lib/x86_64-linux-gnu/libcpuinfo.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/farmhash-build/libfarmhash.so /usr/local/lib/x86_64-linux-gnu/libfarmhash.so

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/base/*.so /usr/local/lib/x86_64-linux-gnu/absl/base
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/debugging/*.so /usr/local/lib/x86_64-linux-gnu/absl/debugging
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/container/*.so /usr/local/lib/x86_64-linux-gnu/absl/container
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/flags/*.so /usr/local/lib/x86_64-linux-gnu/absl/flags
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/hash/*.so /usr/local/lib/x86_64-linux-gnu/absl/hash
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/numeric/*.so /usr/local/lib/x86_64-linux-gnu/absl/numeric
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/profiling/*.so /usr/local/lib/x86_64-linux-gnu/absl/profiling
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/status/*.so /usr/local/lib/x86_64-linux-gnu/absl/status
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/strings/*.so /usr/local/lib/x86_64-linux-gnu/absl/strings
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/synchronization/*.so /usr/local/lib/x86_64-linux-gnu/absl/synchronization
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/time/*.so /usr/local/lib/x86_64-linux-gnu/absl/time
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/_deps/abseil-cpp-build/absl/types/*.so /usr/local/lib/x86_64-linux-gnu/absl/types

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/pthreadpool/libpthreadpool.so /usr/local/lib/x86_64-linux-gnu/

  printf "Copy arm64 lib\n"
  buildah run $containerName mkdir -p \
                                  /usr/local/lib/aarch64-linux-gnu \
                                  /usr/local/lib/aarch64-linux-gnu/absl/base \
                                  /usr/local/lib/aarch64-linux-gnu/absl/debugging \
                                  /usr/local/lib/aarch64-linux-gnu/absl/container \
                                  /usr/local/lib/aarch64-linux-gnu/absl/flags \
                                  /usr/local/lib/aarch64-linux-gnu/absl/hash \
                                  /usr/local/lib/aarch64-linux-gnu/absl/numeric \
                                  /usr/local/lib/aarch64-linux-gnu/absl/profiling \
                                  /usr/local/lib/aarch64-linux-gnu/absl/status \
                                  /usr/local/lib/aarch64-linux-gnu/absl/strings \
                                  /usr/local/lib/aarch64-linux-gnu/absl/synchronization \
                                  /usr/local/lib/aarch64-linux-gnu/absl/time \
                                  /usr/local/lib/aarch64-linux-gnu/absl/types

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/libtensorflow-lite.so /usr/local/lib/aarch64-linux-gnu/libtensorflowlite_c.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/fft2d-build/libfft2d_fftsg.so /usr/local/lib/aarch64-linux-gnu/libfft2d_fftsg.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/fft2d-build/libfft2d_fftsg2d.so /usr/local/lib/aarch64-linux-gnu/libfft2d_fftsg2d.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/xnnpack-build/libXNNPACK.so /usr/local/lib/aarch64-linux-gnu/libXNNPACK.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/cpuinfo-build/libcpuinfo.so /usr/local/lib/aarch64-linux-gnu/libcpuinfo.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/farmhash-build/libfarmhash.so /usr/local/lib/aarch64-linux-gnu/libfarmhash.so

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/base/*.so /usr/local/lib/aarch64-linux-gnu/absl/base
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/debugging/*.so /usr/local/lib/aarch64-linux-gnu/absl/debugging
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/container/*.so /usr/local/lib/aarch64-linux-gnu/absl/container
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/flags/*.so /usr/local/lib/aarch64-linux-gnu/absl/flags
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/hash/*.so /usr/local/lib/aarch64-linux-gnu/absl/hash
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/numeric/*.so /usr/local/lib/aarch64-linux-gnu/absl/numeric
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/profiling/*.so /usr/local/lib/aarch64-linux-gnu/absl/profiling
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/status/*.so /usr/local/lib/aarch64-linux-gnu/absl/status
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/strings/*.so /usr/local/lib/aarch64-linux-gnu/absl/strings
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/synchronization/*.so /usr/local/lib/aarch64-linux-gnu/absl/synchronization
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/time/*.so /usr/local/lib/aarch64-linux-gnu/absl/time
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/_deps/abseil-cpp-build/absl/types/*.so /usr/local/lib/aarch64-linux-gnu/absl/types

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/pthreadpool/libpthreadpool.so /usr/local/lib/aarch64-linux-gnu/

  printf "Copy armhf lib\n"
  buildah run $containerName mkdir -p /usr/local/lib/arm-linux-gnueabihf
  buildah run $containerName mkdir -p \
                                  /usr/local/lib/arm-linux-gnueabihf \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/base \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/debugging \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/container \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/flags \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/hash \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/numeric \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/profiling \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/status \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/strings \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/synchronization \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/time \
                                  /usr/local/lib/arm-linux-gnueabihf/absl/types
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/libtensorflow-lite.so /usr/local/lib/arm-linux-gnueabihf/libtensorflowlite_c.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/fft2d-build/libfft2d_fftsg.so /usr/local/lib/arm-linux-gnueabihf/libfft2d_fftsg.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/fft2d-build/libfft2d_fftsg2d.so /usr/local/lib/arm-linux-gnueabihf/libfft2d_fftsg2d.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/xnnpack-build/libXNNPACK.so /usr/local/lib/arm-linux-gnueabihf/libXNNPACK.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/cpuinfo-build/libcpuinfo.so /usr/local/lib/arm-linux-gnueabihf/libcpuinfo.so
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/farmhash-build/libfarmhash.so /usr/local/lib/arm-linux-gnueabihf/libfarmhash.so

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/base/*.so /usr/local/lib/arm-linux-gnueabihf/absl/base
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/debugging/*.so /usr/local/lib/arm-linux-gnueabihf/absl/debugging
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/container/*.so /usr/local/lib/arm-linux-gnueabihf/absl/container
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/flags/*.so /usr/local/lib/arm-linux-gnueabihf/absl/flags
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/hash/*.so /usr/local/lib/arm-linux-gnueabihf/absl/hash
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/numeric/*.so /usr/local/lib/arm-linux-gnueabihf/absl/numeric
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/profiling/*.so /usr/local/lib/arm-linux-gnueabihf/absl/profiling
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/status/*.so /usr/local/lib/arm-linux-gnueabihf/absl/status
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/strings/*.so /usr/local/lib/arm-linux-gnueabihf/absl/strings
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/synchronization/*.so /usr/local/lib/arm-linux-gnueabihf/absl/synchronization
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/time/*.so /usr/local/lib/arm-linux-gnueabihf/absl/time
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/_deps/abseil-cpp-build/absl/types/*.so /usr/local/lib/arm-linux-gnueabihf/absl/types

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/pthreadpool/libpthreadpool.so /usr/local/lib/arm-linux-gnueabihf/

  buildah commit --rm --manifest "${MANIFEST_TFLITE_BUILDER}" "${containerName}"

}


build_tensorflow_lite

build_tflite_runtime "linux/amd64"
build_tflite_runtime "linux/arm64"
build_tflite_runtime "linux/arm/v7"
buildah manifest push --rm -f v2s2 --all "${MANIFEST_TFLITE_RUNTIME}" "docker://${OCI_REGISTRY}/${MANIFEST_TFLITE_RUNTIME}"

build_tflite_builder
buildah manifest push --rm -f v2s2 --all "${MANIFEST_TFLITE_BUILDER}" "docker://${OCI_REGISTRY}/${MANIFEST_TFLITE_BUILDER}"
