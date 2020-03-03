# docker-coral-edgetpu

![Docker](https://github.com/cyrilix/docker-coral-edgetpu/workflows/Docker/badge.svg?branch=master)

Base image for [coral usb accelerator](https://coral.ai/products/accelerator/)

## Build images

Run:
```bash
docker buildx build . --platform linux/arm/v7,linux/arm64,linux/X86_64 --progress plain
```
