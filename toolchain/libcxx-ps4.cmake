# Cache script: a modern libc++/libc++abi (LLVM 22) for the PS4, against the orbis-sdk-v1 bundle's
# musl libc. The SDK ships libc++ 11, which predates the C++20/23 the rexglue runtime is written in.
#
#   cmake -G Ninja -S llvm-src/runtimes -B build-libcxx -C libcxx-ps4.cmake
#   ninja -C build-libcxx install-cxx install-cxxabi
#
# Mirrors how OpenOrbis configured theirs: _LIBCPP_HAS_MUSL_LIBC, and __FreeBSD__ undefined for
# libc++ (the triple is FreeBSD's but the C library is musl).
if(DEFINED ENV{SKATE3_WORKSPACE})
  file(TO_CMAKE_PATH "$ENV{SKATE3_WORKSPACE}" WORKSPACE)
else()
  get_filename_component(WORKSPACE "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
endif()
set(BUNDLE "${WORKSPACE}/orbis-sdk-v1")
set(SDK "${BUNDLE}/sdk")

set(CMAKE_SYSTEM_NAME FreeBSD CACHE STRING "")  # Generic makes the unused SHARED targets collide with the static ones
set(CMAKE_SYSTEM_PROCESSOR x86_64 CACHE STRING "")
set(CMAKE_C_COMPILER clang CACHE STRING "")
set(CMAKE_CXX_COMPILER clang++ CACHE STRING "")
set(CMAKE_AR llvm-ar CACHE STRING "")
set(CMAKE_RANLIB llvm-ranlib CACHE STRING "")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY CACHE STRING "")
set(CMAKE_BUILD_TYPE Release CACHE STRING "")
set(CMAKE_INSTALL_PREFIX "${WORKSPACE}/libcxx-ps4" CACHE PATH "")

set(_flags "--target=x86_64-pc-freebsd12-elf -march=btver2 -fPIC -funwind-tables -D__PS4__ -DPS4 -D__ORBIS__ -D_BSD_SOURCE=1 -U__FreeBSD__ -isysroot ${SDK} -isystem ${CMAKE_CURRENT_LIST_DIR}/ps4-fixinc -isystem ${BUNDLE}/orbis-compat/include -isystem ${SDK}/include")
set(CMAKE_C_FLAGS "${_flags}" CACHE STRING "")
set(CMAKE_CXX_FLAGS "${_flags} -nostdinc++" CACHE STRING "")
set(CMAKE_ASM_FLAGS "${_flags}" CACHE STRING "")

set(LLVM_ENABLE_RUNTIMES "libcxx;libcxxabi" CACHE STRING "")
set(LIBCXX_ENABLE_SHARED OFF CACHE BOOL "")
set(LIBCXX_ENABLE_STATIC ON CACHE BOOL "")
set(LIBCXXABI_ENABLE_SHARED OFF CACHE BOOL "")
set(LIBCXXABI_ENABLE_STATIC ON CACHE BOOL "")
set(LIBCXX_ENABLE_STATIC_ABI_LIBRARY ON CACHE BOOL "")  # libc++abi merged into libc++.a
set(LIBCXX_CXX_ABI libcxxabi CACHE STRING "")
set(LIBCXX_HAS_MUSL_LIBC ON CACHE BOOL "")
set(LIBCXX_HAS_PTHREAD_API ON CACHE BOOL "")
set(LIBCXXABI_HAS_PTHREAD_API ON CACHE BOOL "")
set(LIBCXXABI_USE_LLVM_UNWINDER OFF CACHE BOOL "")     # keep the SDK's libunwind
set(LIBCXXABI_ENABLE_THREADS ON CACHE BOOL "")
set(LIBCXX_USE_COMPILER_RT OFF CACHE BOOL "")
set(LIBCXXABI_USE_COMPILER_RT OFF CACHE BOOL "")
set(LIBCXX_ENABLE_ABI_LINKER_SCRIPT OFF CACHE BOOL "")
set(LIBCXX_ENABLE_TIME_ZONE_DATABASE OFF CACHE BOOL "")
set(LIBCXX_ENABLE_FILESYSTEM ON CACHE BOOL "")
set(LIBCXX_ENABLE_LOCALIZATION ON CACHE BOOL "")
set(LIBCXX_ENABLE_WIDE_CHARACTERS ON CACHE BOOL "")
set(LIBCXX_HARDENING_MODE none CACHE STRING "")
set(LIBCXX_INCLUDE_TESTS OFF CACHE BOOL "")
set(LIBCXX_INCLUDE_BENCHMARKS OFF CACHE BOOL "")
set(LIBCXX_INCLUDE_DOCS OFF CACHE BOOL "")
set(LIBCXXABI_INCLUDE_TESTS OFF CACHE BOOL "")
set(LLVM_INCLUDE_TESTS OFF CACHE BOOL "")
set(LIBCXX_INSTALL_MODULES OFF CACHE BOOL "")
