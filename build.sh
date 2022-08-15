#! /bin/bash

TENSORFLOW_VERSION=v2.9.0


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

  printf "Build amd64"
  buildah run $containerName mkdir -p /src/build/amd64
  buildah config --workingdir=/src/build/amd64 $containerName

  buildah run $containerName cmake ../../tensorflow/tensorflow/lite/c
  buildah run $containerName cmake --build .

  printf "Build armhf"

  buildah config --workingdir=/src/toolchains/ $containerName
  buildah run $containerName curl -LO https://storage.googleapis.com/mirror.tensorflow.org/developer.arm.com/media/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz
  buildah run $containerName tar xvf gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz -C /src/toolchains

  buildah run $containerName mkdir -p /src/build/armhf

  buildah config --workingdir=/src/build/armhf $containerName
  CC_FLAGS="-march=armv7-a -mfpu=neon-vfpv4 -funsafe-math-optimizations"
  ARMCC_PREFIX=/src/toolchains/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf/bin/arm-linux-gnueabihf-

  buildah run $containerName cmake \
                  -DCMAKE_C_COMPILER=${ARMCC_PREFIX}gcc \
                  -DCMAKE_CXX_COMPILER=${ARMCC_PREFIX}g++ \
                  -DCMAKE_C_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_CXX_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
                  -DCMAKE_SYSTEM_NAME=Linux \
                  -DCMAKE_SYSTEM_PROCESSOR=armv7 \
                  ../../tensorflow/tensorflow/lite/c
  buildah run $containerName cmake --build .


  printf "Build arm64"

  buildah config --workingdir=/src/toolchains/ $containerName
  buildah run $containerName curl -LO https://storage.googleapis.com/mirror.tensorflow.org/developer.arm.com/media/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz
  buildah run $containerName tar xvf gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz -C /src/toolchains

  buildah run $containerName mkdir -p /src/build/arm64

  buildah config --workingdir=/src/build/arm64 $containerName
  CC_FLAGS="-funsafe-math-optimizations"
  ARMCC_PREFIX=/src/toolchains/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu/bin/aarch64-linux-gnu-

  buildah run $containerName cmake \
                  -DCMAKE_C_COMPILER=${ARMCC_PREFIX}gcc \
                  -DCMAKE_CXX_COMPILER=${ARMCC_PREFIX}g++ \
                  -DCMAKE_C_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_CXX_FLAGS="${CC_FLAGS}" \
                  -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
                  -DCMAKE_SYSTEM_NAME=Linux \
                  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
                  ../../tensorflow/tensorflow/lite/c
  buildah run $containerName cmake --build .
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

  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/$BINARY_ARCH/libtensorflowlite_c.so /usr/local/lib/libtensorflowlite_c.so

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
  buildah run $containerName mkdir -p /usr/local/lib/x86_64-linux-gnu
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/amd64/libtensorflowlite_c.so /usr/local/lib/x86_64-linux-gnu/libtensorflowlite_c.so

  printf "Copy arm64 lib\n"
  buildah run $containerName mkdir -p /usr/local/lib/aarch64-linux-gnu
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/arm64/libtensorflowlite_c.so /usr/local/lib/aarch64-linux-gnu/libtensorflowlite_c.so

  printf "Copy armhf lib\n"
  buildah run $containerName mkdir -p /usr/local/lib/arm-linux-gnueabihf
  buildah copy --from=$CONTAINER_TFLITE $containerName /src/build/armhf/libtensorflowlite_c.so /usr/local/lib/arm-linux-gnueabihf/libtensorflowlite_c.so

  buildah commit --rm --manifest "${MANIFEST_TFLITE_BUILDER}" "${containerName}"

}


#build_tensorflow_lite

#build_tflite_runtime "linux/amd64"
#build_tflite_runtime "linux/arm64"
#build_tflite_runtime "linux/arm/v7"
#buildah manifest push --rm -f v2s2 --all "${MANIFEST_TFLITE_RUNTIME}" "docker://${OCI_REGISTRY}/${MANIFEST_TFLITE_RUNTIME}"

build_tflite_builder
buildah manifest push --rm -f v2s2 --all "${MANIFEST_TFLITE_BUILDER}" "docker://${OCI_REGISTRY}/${MANIFEST_TFLITE_BUILDER}"
