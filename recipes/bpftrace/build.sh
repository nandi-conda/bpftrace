set -euo pipefail

# bpftrace's cmake/FindLibBcc.cmake, FindLibElf.cmake, FindLibCereal.cmake and
# FindLibPcap.cmake search CPATH and LIBRARY_PATH only.
export CPATH="${PREFIX}/include${CPATH:+:${CPATH}}"
export LIBRARY_PATH="${PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"

# ccache is a cache, not a dependency of the build: use it when it is present
# and compile normally when it is not, so the recipe still builds for anyone
# who runs rattler-build directly without the pixi task's CCACHE_DIR.
ccache_launchers=""
if command -v ccache >/dev/null 2>&1; then
  ccache_launchers="-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
fi

# libbpf is not a conda package: it is the vendored submodule, which
# rattler-build checks out, so USE_SYSTEM_LIBBPF stays off (the default).
# BUILD_TESTING=OFF skips the unit tests (they need a kernel and root).
#
# LibBfd/LibOpcodes are disabled on purpose. conda-forge's binutils ships the
# static libbfd.a and libopcodes.a but no libiberty.a, so upstream's probe of
# libbfd fails at configure time on some runners (it needs LIBIBERTY_LIBRARIES)
# and succeeds on others, depending on the binutils build. Disabling it makes
# the build deterministic, drops a static-binutils link, and costs nothing:
# HAVE_BFD_DISASM only feeds the debug-build disassembler and `--info`.
cmake -S . -B build -G Ninja \
  $ccache_launchers \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DLLVM_REQUESTED_VERSION="${LLVM_VERSION}" \
  -DBUILD_TESTING=OFF \
  -DENABLE_MAN=ON \
  -DUSE_SYSTEM_LIBBPF=OFF \
  -DCMAKE_DISABLE_FIND_PACKAGE_LibBfd=TRUE \
  -DCMAKE_DISABLE_FIND_PACKAGE_LibOpcodes=TRUE

cmake --build build --parallel "${CPU_COUNT:-$(nproc)}"
cmake --install build
