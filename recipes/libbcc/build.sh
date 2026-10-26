set -euo pipefail

# bcc's own CMake modules look dependencies up through CPATH and LIBRARY_PATH,
# which do not contain the host prefix by default.
export CPATH="${PREFIX}/include${CPATH:+:${CPATH}}"
export LIBRARY_PATH="${PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"

# ccache is a cache, not a dependency of the build: use it when it is present
# and compile normally when it is not, so the recipe still builds for anyone who
# runs rattler-build directly without ccache in the build environment.
ccache_launchers=""
if command -v ccache >/dev/null 2>&1; then
  ccache_launchers="-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
fi

# ENABLE_LLVM_SHARED links libLLVM and libclang-cpp as shared libraries instead
# of --whole-archive'ing the static archives, so libbcc.so carries no private
# copy of LLVM next to the one bpftrace links.
# bpftrace only needs the libraries and headers, so the extras are off.
cmake -S . -B build -G Ninja \
  $ccache_launchers \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DENABLE_LLVM_SHARED=ON \
  -DENABLE_LLVM_NATIVECODEGEN=ON \
  -DENABLE_TESTS=OFF \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_MAN=OFF \
  -DENABLE_LIBDEBUGINFOD=OFF \
  -DINSTALL_INTROSPECTION=OFF

cmake --build build --parallel "${CPU_COUNT:-$(nproc)}"
cmake --install build
