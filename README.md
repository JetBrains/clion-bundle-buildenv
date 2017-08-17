# dockerfile-gdb-build
Dockerfile for building GDB for MinGW-W64

## Building
Run the `~/build.sh` script inside a Docker container:
```
./build.sh makepkg-mingw32.conf gdb
```

Artifacts will appear in the `~/artifacts` directory:
```
$ ls i686-gdb-*
i686-gdb-8.0-2-any.pkg.tar.xz  i686-gdb-8.0-2-dll-dependencies.tar.xz
```
