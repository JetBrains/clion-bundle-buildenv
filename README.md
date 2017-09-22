# dockerfile-gdb-build
Dockerfiles and PKGBUILD scripts for building GDB for MinGW-W64 and Linux


## Building

### MinGW-W64

Run the Docker container with the repository root (containing `build.sh`) mounted as `/workdir`:
```
docker run -v $(pwd):/workdir -it abusalimov/gdb-build-mingw-w64:latest
```

Run the `~/build.sh` script inside the Docker container:
```
cd mingw-w64
../build.sh -c makepkg-mingw32.conf -- gdb python3-embed-prebuilt
```
(Use `makepkg-mingw64.conf` to build 64-bit packages instead.)

Artifacts will appear in the `mingw-w64/artifacts` directory:
```
$ ls mingw-w64/artifacts/bundle-*.tar.xz
mingw-w64/artifacts/bundle-i686-w64-mingw32.tar.xz
```


### Linux

Run the Docker container with the repository root (containing `build.sh`) mounted as `/workdir`:
```
docker run -v $(pwd):/workdir -it abusalimov/gdb-build-linux:latest
```

Run the `~/build.sh` script inside the Docker container:
```
cd linux
../build.sh -c makepkg-linux.conf -- gdb
```

Artifacts will appear in the `linux/artifacts` directory:
```
$ ls linux/artifacts/bundle-*.tar.xz
linux/artifacts/bundle-x86_64-pc-linux-gnu.tar.xz
```

