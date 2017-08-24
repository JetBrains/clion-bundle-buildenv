# dockerfile-gdb-build
Dockerfiles and PKGBUILD scripts for building GDB for MinGW-W64 and Linux


## Building

### MinGW-W64

Run the Docker container with `~/host/path/to/artifacts` mounted as the artifacts directory:
```
docker run -v ~/host/path/to/artifacts:/home/build/artifacts -it abusalimov/gdb-build-mingw-w64:latest
```

Run the `~/build.sh` script inside the Docker container:
```
./build.sh -c makepkg-mingw32.conf gdb python3-embed-prebuilt
```
(Use `makepkg-mingw64.conf` to build 64-bit packages instead.)

Artifacts will appear in the `~/host/path/to/artifacts` directory:
```
$ ls bundle-*.tar.xz
bundle-i686-w64-mingw32.tar.xz
```


### Linux

Run the Docker container with `~/host/path/to/artifacts` mounted as the artifacts directory:
```
docker run -v ~/host/path/to/artifacts:/home/build/artifacts -it abusalimov/gdb-build-linux:latest
```

Run the `~/build.sh` script inside the Docker container:
```
./build.sh -c makepkg-linux.conf gdb
```

Artifacts will appear in the `~/host/path/to/artifacts` directory:
```
$ ls bundle-*.tar.xz
bundle-x86_64-pc-linux-gnu.tar.xz
```
