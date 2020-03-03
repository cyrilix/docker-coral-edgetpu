FROM python:3.7

ENV TF_VERSION=2.1.0 \
    PYTHON_VERSION=37


RUN echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    apt-get update && \
    apt-get install -y libedgetpu1-std && \
    pip3 install https://dl.google.com/coral/python/tflite_runtime-${TF_VERSION}.post1-cp${PYTHON_VERSION}-cp${PYTHON_VERSION}m-$(uname --kernel-name)_$(uname --machine).whl

USER 1234
