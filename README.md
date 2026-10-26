# bpftrace for pixi/conda

Packages [bpftrace](https://bpftrace.org) — and the `libbcc` it cannot be built
without — as conda packages, and publishes them to the `nandi-testing` channel on
[prefix.dev](https://prefix.dev), so any pixi project can use the tracer without
a distro package:

```sh
pixi add --channel https://prefix.dev/nandi-testing bpftrace
```

[GitHub Actions](.github/workflows/build.yaml) compiles both packages on every
push to `main` and uploads them; nothing has to be built on a workstation.

## What has to be packaged, and why

conda-forge has no `bpftrace`, and it also has no `libbcc`, which bpftrace
hard-requires (`CMakeLists.txt`: `find_package(LibBcc REQUIRED)` for
`bcc/bcc_syms.h`, `libbcc.so` and `libbcc_bpf.so`). So this repository builds two
packages, in order:

| Package | Source | Why it is here |
| --- | --- | --- |
| `libbcc` | [iovisor/bcc](https://github.com/iovisor/bcc) `v0.37.0` | On no channel, and bpftrace will not configure without it. Ships the C/C++ libraries, headers and `libbcc.pc` only. |
| `bpftrace` | [bpftrace/bpftrace](https://github.com/bpftrace/bpftrace) `v0.27.1` | The point of the repository. |

Everything else comes from conda-forge — no further packaging is needed:

| Dependency | Note |
| --- | --- |
| `llvmdev`, `clangdev` 20.1 | bpftrace accepts LLVM 18–23 and bcc carries guards up to 22, so 20.1 is the overlap both are happy with. |
| `libllvm20`, `libclang-cpp20.1`, `libclang13` | The shared libraries both binaries link; keeping them shared keeps the packages at ~2 MB and ~4 MB instead of embedding LLVM twice. |
| `elfutils` | `libelf` and `libdw`. |
| `cereal` | Header-only, needed to parse the AST at build time. |
| `libpcap` | `skb_output` probes. |
| `liblzma`, `liblzma-devel` | bcc compresses ELF sections with liblzma when it can; conda-forge splits the header and `.so` into the `-devel` package. |
| **`libbpf`** | **Not packaged.** It is a git submodule of both bcc and bpftrace; rattler-build checks submodules out, which is upstream's default build. |

Disassembly of the generated BPF is deliberately switched off
(`-DCMAKE_DISABLE_FIND_PACKAGE_LibBfd`). conda-forge's `binutils` ships
`libbfd.a` and `libopcodes.a` but no `libiberty.a`, so bpftrace's configure probe
of libbfd fails on some machines and succeeds on others; `HAVE_BFD_DISASM` only
feeds the debug-build disassembler and `--info`, so turning it off keeps every
build identical.

## Layout

```
pixi.toml                  tasks: bcc, bpftrace, build, smoke, publish
recipes/libbcc/            recipe.yaml + build.sh   (bcc 0.37.0)
recipes/bpftrace/          recipe.yaml + build.sh   (bpftrace 0.27.1, links ./output's libbcc)
.github/workflows/build.yaml  builds both and publishes on push to main
```

## Building locally (optional — CI does this)

```sh
pixi run build      # libbcc, then bpftrace against it from ./output
pixi run smoke      # install the built packages in a scratch env and run bpftrace
pixi run bcc        # just libbcc
pixi run bpftrace   # just bpftrace
```

Both build scripts use ccache when the build environment has it, with the cache
at `/tmp/bpftrace-conda-ccache` and `--no-build-id` on the tasks so compiler
command lines stay byte-identical between runs. That is what makes repeat builds
fast; neither the cache nor the directory is required for a correct build.

When a recipe changes, bump its `build.number`. The `${{ hash }}` in the build
string only covers the variant, so an edited recipe otherwise reuses the previous
package file name.

## Publishing

The channel needs an API key with write access to it:

- **CI:** repository secret `PREFIX_API_KEY` (Settings → Secrets and variables →
  Actions). Until it is set, CI builds and smoke-tests but only warns that the
  upload was skipped.
- **Locally:** `export PREFIX_API_KEY=…` and then `pixi run publish`.

`pixi run publish` uploads whatever is in `output/linux-64/*.conda` with
`--skip-existing`, so re-running it after a partial failure is safe.

## Runtime requirements on the machine that installs bpftrace

- `linux-64`. `linux-aarch64` is declared in `pixi.toml`, but nothing builds or
  tests it yet.
- **root** (or `CAP_BPF`/`CAP_PERFMON` plus `CAP_DAC_READ_SEARCH`) — bpftrace
  needs it, exactly like a distro package. `bpftrace --version` works unprivileged;
  everything else does not.
- A kernel with BTF (`/sys/kernel/btf/vmlinux`) and the host's libc headers on
  disk under `/usr/include`: bpftrace compiles the probe at runtime. The kernel
  and libbpf headers themselves are vendored into the binary, so no
  `linux-headers` package is needed, but a host without `/usr/include` (NixOS)
  will not work.
- `SYSTEM_INCLUDE_PATHS` is left at `auto`, i.e. upstream's default: bpftrace
  runs `clang-20` if one is on `PATH` and falls back to
  `/usr/local/include:/usr/include` when it is not — which is the distro
  behaviour.

## Known gaps

- `libbcc` ships no python bindings, no `tools/` and no `bps`; bpftrace needs
  none of them.
- No probe is attached in CI: that needs root, which the runner does not have.
  `pixi run smoke` proves every shared library loads, not that a probe attaches.
  The real check is on a machine with privileges:
  `sudo bpftrace -e 'BEGIN { printf("ok\n"); exit(); }'`
- No automated version bumps; `version:` in both recipes and the `libbcc` pin in
  `recipes/bpftrace/recipe.yaml` have to move together.
- `linux-aarch64` and macOS are out of scope.
