# Skate 3 on PS4 — XeMoisties

Skate 3 (Xbox 360) running natively on a jailbroken PS4 as a homebrew pkg. Not emulation: the
360 game code is statically recompiled to x86-64 and runs on the PS4's Jaguar CPU, with the
graphics going through Vulkan (Mesa RADV for PS4) straight to VideoOut.

Status: the whole game is playable. Boot, intro videos, career intro, team/player name entry with
the PS4 on-screen keyboard, and free roam. ~60 fps standing still, drops toward 30-40 in busy
scenes. Videos are smooth. There's an all-in-one (AIO) pkg that carries the game files, a starter
save and settings, so a console only needs the one pkg.

This repo is the write-up of how I got it there, start to finish, plus every patch, script and
config needed to rebuild it. It does **not** contain any game files, recompiled game code or
saves — you need your own copy of Skate 3.

- [How it works](#how-it-works)
- [What you need](#what-you-need)
- [Building it](#building-it)
- [Packaging (normal pkg and AIO)](#packaging)
- [The journey: every problem and how I fixed it](#the-journey)
- [Performance work](#performance-work)
- [Debugging tools I built](#debugging-tools)
- [Repo layout](#repo-layout)
- [Credits](#credits)

---

## How it works

The base is [skate3recomp](https://github.com/mchughalex/skate3recomp), a PC port of Skate 3 built
on the ReXGlue SDK (a Xenia-derived runtime for statically recompiled 360 games). Its codegen turns
the 360's PowerPC code (default.xex + the TU3 patch) into C++, one function per guest function,
and the runtime supplies the Xbox kernel, the GPU command processor, audio (XMA through FFmpeg),
input, file system and so on. Skate 3 also has a native Vulkan/D3D12 scene renderer on top of the
emulated GPU path.

Getting that onto a PS4 meant:

1. A modern C++ toolchain for the PS4 (the OpenOrbis SDK ships libc++ 11; the runtime needs C++23).
2. A PS4 platform layer for the runtime: memory, threads, fibers, signals/faults, video output,
   audio, pad input, windowing, the on-screen keyboard.
3. Fixing everything that broke on real hardware (a lot, see below).
4. Making it fast enough on a 1.6 GHz Jaguar.
5. Packaging it as a fake pkg, and later an AIO pkg.

Stack on the console:

```
recompiled Skate 3 (C++)  ─┐
ReXGlue runtime (PS4 port) ─┼─ libc++ 22 / musl (OpenOrbis) / rpmalloc
FFmpeg (XMA audio, VP6 video)┘
Vulkan ── Mesa RADV (orbis-ports) ── Gnm/GPU;  VK_EXT_headless_surface ── sceVideoOut flips
sceAudioOut · scePad · sceImeDialog · sceUserService · sceKernel*
```

---

## What you need

**Hardware / console**
- A jailbroken PS4 with GoldHEN (I use FW 9.00). FTP on (GoldHEN → Settings → Server Settings).
- ~13 GB free to install the AIO pkg (6.5 GB pkg + install).

**Game**
- Skate 3 (USA/Europe) Xbox 360 disc, extracted (default.xex, data/, ...).
- Title Update 3 (`TU_12K2276_000000C000000.00000000000O3`), staged as `default.xexp` (and the
  EAWebkit xexp) next to the game files — skate3recomp's installer does this on PC.

**PC (Windows, no WSL needed)**
- Visual Studio 2022+ with "MSVC x64 build tools" + Windows SDK (only for the host-side codegen and
  the PC build).
- LLVM/clang 22, CMake 4.x, Ninja, Python 3, .NET runtime (for PkgTool).
- The orbis-ports PS4 bundle `orbis-sdk-v1` (OpenOrbis 0.5.4 + orbis-compat + prebuilt Mesa RADV +
  the vkloader shim).
- OpenOrbis `create-gp4` / `PkgTool.Core`, and a patched `orbis-pub-cmd` (3.87) for the AIO.
- LLVM 22.1.8 source (for building libc++/libc++abi for the PS4).

---

## Building it

### 0. Workspace

Everything lives side by side in one folder (the scripts find things relative to it — set
`SKATE3_WORKSPACE` if you want it elsewhere, and put your console's IP in
[`scripts/config.ps1`](scripts/config.ps1) or the `PS4_IP` environment variable):

```
<workspace>\
  skate3-ps4-port\     this repo
  skate3recomp\        skate3recomp clone (patched below), game\ = your extracted game + TU3
  orbis-sdk-v1\        orbis-ports PS4 bundle
  oo054\               OpenOrbis v0.5.4 release (libc.prx / libSceFios2.prx for the pkg)
  libcxx-ps4\          libc++ 22 for the PS4 (built in step 2)
  art\                 icon0.png (512x512), pic1.png (1920x1080), optional defaults\save\ (see Packaging)
  tools\orbis-pub-cmd.exe   patched Sony publishing tool, only for the AIO
```

### 1. Get the PC build working first

Clone skate3recomp with submodules, put the extracted game + TU3 in `game/`, and build the PC
version (`cmake --preset relwithdebinfo`, then `--target generate-all`, then build). This runs the
codegen that produces `generated/` from your own xex. Make sure the PC build boots before touching
the PS4 side — it's the reference for everything.

### 2. PS4 toolchain

Everything is in [`toolchain/`](toolchain):

- `env.ps1` — puts VS build tools, LLVM, CMake and Ninja on PATH. For PS4 builds remove `CC`/`CXX`
  after dot-sourcing it.
- `libcxx-ps4.cmake` — cache file to build **libc++ / libc++abi 22** against the SDK's musl:
  `CMAKE_SYSTEM_NAME FreeBSD`, `-U__FreeBSD__`, `-march=btver2`, `LIBCXX_HAS_MUSL_LIBC`, static
  abi. Apply [`patches/llvm-libcxx.patch`](patches/llvm-libcxx.patch) to the LLVM source first
  (Orbis uses the Linux locale support, declares the `strto*_l` functions, and uses the fstream
  path for filesystem copies because there's no `copy_file_range`/usable `sendfile`).
- `ps4-fixinc/` — header overrides: a `math.h` without OpenOrbis's C++ overloads (they clash with
  libc++), `bits/signal.h` with **FreeBSD signal numbers** (the SDK ships Linux ones: SIGBUS 7,
  SIGUSR1 10 — wrong on PS4), and `signal.h` with SIGRTMIN 65.
- `ps4-modern.cmake` — the CMake toolchain file: the orbis bundle's toolchain + the new libc++ +
  the fixinc overlay + the right link line.

### 3. Apply the patches

```
cd skate3recomp
git apply ../patches/skate3recomp.patch
cd third_party/rexglue-sdk
git apply ../../../patches/rexglue-sdk.patch
(cd thirdparty/FFmpeg  && git apply ../../../../../patches/rexglue-sdk-FFmpeg.patch)
(cd thirdparty/glslang && git apply ../../../../../patches/rexglue-sdk-glslang.patch)
```

imgui: the pinned submodule commit is gone upstream; I build against `d94d0f364` with the
`RasterizerGamma` lines in `imgui_drawer.cpp` commented out (already in the SDK patch).

After (re)running codegen, re-apply the `REX_PHYS_HOST_OFFSET` change to `generated/*_init.h`
(the template `init_h.inja` is patched, but hand-generated headers need it too): the PS4's 16 KB
pages mean the 0xE0000000+ physical window gets the same +0x1000 host offset as Windows.

### 4. Configure and build

```
cmake -S . -B out/build/ps4 -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=<path>/toolchain/ps4-modern.cmake \
  -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_ENABLE_PERF_COUNTERS=ON
ninja -C out/build/ps4 skate3
```

Output is `out/build/ps4/eboot.bin`. [`scripts/deploy-skate3.ps1`](scripts/deploy-skate3.ps1)
does build → pkg → FTP upload to `/data/pkg/Skate3.pkg` in one go.

---

## Packaging

**Normal pkg** — [`scripts/make-pkg.ps1`](scripts/make-pkg.ps1): a Windows port of orbis-compat's
make-pkg. Writes param.sfo, stages eboot + libc/libSceFios2 prx + icon/background + extras,
runs `create-gp4`, fixes up the gp4 (create-gp4 only declares a fixed set of folders — PkgTool
dies with "Sequence contains no elements" on anything else, so the script declares every folder a
file lives in) and builds with `PkgTool.Core`. Title id `SKAT00001`.

**AIO pkg** — [`scripts/make-aio.ps1`](scripts/make-aio.ps1): same staging, plus the whole game
folder packed in place (gp4 entries with absolute `orig_path`, no 6 GB copy), plus
`defaults/settings.toml` and a starter save. PkgTool.Core crashes on a package that size, so the
final pack is done with the patched Sony `orbis-pub-cmd img_create --oformat pkg --skip_digest`.
That tool also needs `FORMAT=obs` in param.sfo and no empty `sce_sys/about` folder.

At launch the eboot:
- uses `/data/skate3/game` if it exists, otherwise `/app0/game` (the AIO's own files);
- copies `defaults/settings.toml` and the starter save into `/data/skate3` only if missing;
- sets the GPU arena (`ORBIS_ARENA_MIB=2048`) itself;
- the starter save is optional: drop `SKATER.P`, `RMCDEL` and `ALIAS_SKATER.header` from a console
  (`/data/skate3/B13E07DFF9AB6772/454108E6/...`) into `art\defaults\save\` and the scripts pack it;
- if no game files are found anywhere, shows a notification saying where to put them instead of
  crashing;
- shows a "Compiled by XeMoisties | CyprusNetwork" notification and hides the splash.

Logging is **off** in release. Dropping a `debug.txt` into `/data/skate3` turns the log, boot notes,
crash reports and the stall watchdog back on.

`config/settings.toml` is the PS4 profile. On top of that, the PS4 build force-sets the settings
that must stay PS4-safe (1x resolution, draw distance/LOD ≤ 1, no MSAA/SSAO/shafts/PCSS, 1024
shadow maps, camera smoothing off) after any settings file or profile loads — a fresh console gets
the PC defaults (2x resolution wants a 2 GB resolve buffer) and crashed at boot before this.

---

## The journey

Roughly in the order I hit them.

### Platform probe
Before porting the runtime I wrote a small test pkg that checks every hard requirement on real
hardware and shows a green or red screen. What it established:
- `sceKernelReserveVirtualRange` needs 16 KB-rounded lengths (unrounded → `0x80020016`).
- Direct memory can be mapped at several virtual addresses at once (needed for the 360's aliased
  memory views). A 4 KB-shifted view is refused → `REX_PHYS_HOST_OFFSET`.
- mprotect write-watch → SIGSEGV → unprotect → retry works. PS4 ucontext offsets: mcontext at
  +64, rip +224, rsp +248, rbp +136, err +216, xmm at +480. sigaction needs the corrected SA_*
  flags.
- A C++ `throw` out of a signal handler kills the process — use `siglongjmp`. After siglongjmp
  MXCSR is 0 (every FP exception unmasked), which crashed later in VideoOut with SIGFPE — save and
  restore it. The PS4's default MXCSR is 0x9FC0 (FTZ/DAZ); guest threads get 0x1F80.
- `getcontext`/`makecontext` are broken → fibers use a hand-written asm context switch.
- `pthread_suspend_np`/`resume_np`, `pthread_kill`, affinity all work.

### Runtime port (the big chunk)
- **Memory** (`memory_ps4.cpp`): the 360's physical memory is backed by direct memory in 1 MB
  chunks, committed on demand or on first touch (the fault handler maps it in), and mapped at every
  aliasing view.
- **Threads**: FreeBSD signal numbers, `pthread_set_name_np`, no robust mutexes, Orbis priorities
  (256–767, so no SCHED_FIFO), host stacks from pooled **direct** memory (pthread stacks come out of
  the ~400 MB flexible pool and ran out after a handful of 16 MB stacks).
- **Fibers**: asm switch. **Dynamic libs**: the Vulkan "library" is the statically linked loader.
- **Video**: `PS4DisplaySurface` + `VK_EXT_headless_surface`; Mesa's WSI turns presents into
  sceVideoOut flips. PS4 window/app context/main (args from `/data/skate3/args.txt`, `env NAME=VALUE`
  lines supported).
- **Audio**: sceAudioOut float stereo, 48 kHz, one blocking output thread.
- **Input**: scePad mapped to XInput (Cross=A, Circle=B, Square=X, Triangle=Y, OPTIONS=Start,
  touchpad=Back, stick Y inverted).
- The runtime is linked `--whole-archive`: kernel exports register through static constructors in
  otherwise-unreferenced files. Pass it as **one** `-Wl,--whole-archive,<lib>,--no-whole-archive`
  token — CMake de-duplicates repeated identical flags and half of RADV went missing once.

### Boot bugs, in order
1. `getpwuid` returns null → the user folder is `/data` on PS4, `HOME` is set.
2. **Never link `-lSceLibcInternal`**: Sony's `fopen` with musl's `fwrite` = FILE layout mismatch →
   null call.
3. The GPU texture cache wanted 2 GB at the desktop's 2x resolution → PS4 settings at 1x.
4. Thread creation failed (`C0000017`) → stacks from direct memory, no small priority numbers.
5. Missing XamParty exports → whole-archive (and then the de-dup problem above).
6. **Image corruption from the TU patch**: the delta patch copies overlapping ranges with `memcpy`;
   musl's memcpy copies forward and trashed the image (a table at 0x8210A310 turned into shifted
   text). Three copies in `lzx.cpp`/`xex_module.cpp` → `memmove`. Compared the loaded image against
   a PC dump to find it.
7. GPU starvation → `ORBIS_ARENA_MIB=2048` (the 1 GB default is eaten by the 512 MB shared memory).
8. The "Welcome to Skate 3" dialog ignored A → `XInputGetKeystroke` was returning EMPTY; it's now
   emulated exactly like the SDL driver (edges → KEYDOWN/KEYUP, 400 ms repeat delay, 100 ms rate).
9. **The Welcome dialog froze the screen** (the game kept running, the display didn't). The
   presenter's "paint already requested" flag got stuck true, so every later request was dropped. I
   added a stall watchdog that dumps the paint/swap/present counters and found it: on PS4 the
   request is always forwarded (the PS4 window coalesces requests itself).
10. Black screen at the team name screen → the game was waiting on the Xbox keyboard. On PS4
    `XamShowKeyboardUI` now opens the system keyboard (`sceImeDialog`; note SCE's wchar_t is 16-bit
    so the param block is declared with `char16_t`, 0x60 bytes).
11. Out-of-memory crashes in free roam (see memory below).

---

## Performance work

The game is CPU-bound on Jaguar. I added a sampling profiler (ITIMER_PROF → per-thread histograms,
callers, and per-export kernel call counts) and went through it thread by thread.

| Fix | Win |
|---|---|
| `fma`: Jaguar has no FMA unit, recompiled `fmadd` called musl's exact software fma | ~12% of all CPU → inline multiply-add (`-fno-builtin-fma` + inline `fma` in `intrinsics.h`) |
| `WaitMultiple` polled every handle each 1 ms (sleep + try_lock storms) | per-handle waiter registration, wake only the waiters of the signalled handle (the game sets ~68k events/s) |
| D3D wait-for-GPU loop (`db16cyc` compiles to nothing → flat-out spin) | override with progressive back-off: pause → yield → short sleep |
| Job-system claim loop on the main thread | same back-off |
| Shader-name `strstr` on every draw (water/ocean/LED checks) | cached per shader object |
| 1 kHz camera sampler thread (for high-refresh PC displays) | off on PS4 |
| **VP6 video**: the game's own decoder (12k lines of recompiled VMX128) needed 3 cores and still ran at a few fps | replaced with **FFmpeg's VP6 decoder** at `VideoDecoder_Vp6::Decode` (`sub_82AA7218`): decode the packet, call the game's callback for the output `VideoRenderable`, write Y/U/V (rows reversed — VP6 is bottom-up), mark the frame ready. The game still does container parsing, timing and audio. |

Net: from ~5.2 busy cores to ~4.2–4.8 in free roam, loading into the city ~35% faster, smooth
videos.

**Memory.** Free roam ran the flexible pool (~450 MB, where malloc lives) down to 13 MB and died on
the next allocation. Fixes:
- malloc/free/new for the whole process → **rpmalloc** (`src/core/ps4_rpmalloc/`), fed from 16 MB
  chunks of flexible memory while plenty is left, then direct memory. 256 KB span mapping and an
  adaptive thread cache (the default 4 MB-per-thread mapping reserved 512 MB by the main menu with
  ~100 threads).
- Guest host stacks 16 MB → 4 MB (~1 GB of direct memory back). Every thread has an alternate
  signal stack so a stack overflow still produces a crash report.

---

## Debugging tools

All off in release; put a `debug.txt` in `/data/skate3` to turn them on.

- `/data/skate3/boot.txt` (step marks), `crash.txt` (signal, registers, thread name, stack scan of
  return addresses), `stall.txt` (display stall watchdog), `log.txt`.
- **Profiler**: `env REX_PS4_PROFILE_SECONDS=10` and `env REX_PS4_PROFILE_DELAY=5` lines in
  `/data/skate3/args.txt` → `profile_N.txt` per window: sample histogram, `T` per-thread totals,
  `TR` per-thread top addresses, `C` (address, caller) pairs and `K` kernel export call counts.
  Symbolise addresses as runtime address − 0x400000 against `llvm-nm -n -C skate3` — keep a symbol
  file per build, addresses move every build.
- GoldHEN's klog (TCP 3232) shows crash dumps; only one reader at a time.
- [`scripts/tools/fetch.py`](scripts/tools/fetch.py) pulls boot/crash/log over FTP,
  [`upload_game.py`](scripts/tools/upload_game.py) is a resumable FTP upload of the game folder (if
  you're not using the AIO).

---

## Repo layout

```
patches/        skate3recomp, ReXGlue SDK, FFmpeg, glslang and libc++ changes
toolchain/      env.ps1, ps4-modern.cmake, libcxx-ps4.cmake, ps4-fixinc/
scripts/        config.ps1, deploy-skate3.ps1, make-pkg.ps1, make-aio.ps1, tools/ (FTP helpers)
config/         settings.toml (the PS4 profile packed into every pkg)
```

---

## Credits

- [mchughalex/skate3recomp](https://github.com/mchughalex/skate3recomp) and the ReXGlue SDK — the
  PC recompilation this is built on.
- Xenia — the runtime ReXGlue derives from.
- OpenOrbis, orbis-ports (orbis-compat, Mesa RADV for PS4), GoldHEN.
- FFmpeg (XMA + VP6), rpmalloc (public domain, Mattias Jansson).
- EA Black Box for Skate 3. This project ships no game content; bring your own legally owned copy.

— XeMoisties · CyprusNetwork
