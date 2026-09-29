# PS4 toolchain for C++20/23 projects: the orbis-sdk-v1 bundle, with its libc++ 11 swapped for the
# libc++ 22 built by libcxx-ps4.cmake (installed in <workspace>/libcxx-ps4).
#
#   cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE=<workspace>/skate3-ps4-port/toolchain/ps4-modern.cmake ...
#
# What changes relative to toolchain/orbis-sdk.cmake:
#   - C++ headers: libcxx-ps4 instead of sdk/include/c++/v1 (-nostdinc++ keeps the old ones out)
#   - ps4-fixinc first on every include path: a math.h without OpenOrbis's C++ overloads, which
#     collide with libc++ >= 17's own
#   - __FreeBSD__ undefined everywhere, as libc++ was built (the triple is FreeBSD, libc is musl)
#   - libc++.a (with libc++abi merged in) + the SDK's libunwind instead of -lc++
if(DEFINED ENV{SKATE3_WORKSPACE})
  file(TO_CMAKE_PATH "$ENV{SKATE3_WORKSPACE}" PS4_WORKSPACE)
else()
  get_filename_component(PS4_WORKSPACE "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
endif()
include("${PS4_WORKSPACE}/orbis-sdk-v1/toolchain/orbis-sdk.cmake")

set(PS4_LIBCXX "${PS4_WORKSPACE}/libcxx-ps4")
set(PS4_FIXINC "${CMAKE_CURRENT_LIST_DIR}/ps4-fixinc")

string(REPLACE "-isystem ${OO_PS4_TOOLCHAIN}/include/c++/v1"
       "-nostdinc++ -isystem ${PS4_LIBCXX}/include/c++/v1 -isystem ${PS4_FIXINC}"
       CMAKE_CXX_FLAGS_INIT "${CMAKE_CXX_FLAGS_INIT}")
string(REPLACE "-isystem ${ORBIS_COMPAT_DIR}/include -isystem ${OO_PS4_TOOLCHAIN}/include"
       "-isystem ${PS4_FIXINC} -isystem ${ORBIS_COMPAT_DIR}/include -isystem ${OO_PS4_TOOLCHAIN}/include"
       CMAKE_C_FLAGS_INIT "${CMAKE_C_FLAGS_INIT}")
set(CMAKE_C_FLAGS_INIT "${CMAKE_C_FLAGS_INIT} -U__FreeBSD__")
set(CMAKE_CXX_FLAGS_INIT "${CMAKE_CXX_FLAGS_INIT} -U__FreeBSD__")

set(CMAKE_C_STANDARD_LIBRARIES
    "-lc -lkernel ${PS4_LIBCXX}/lib/libc++.a ${OO_PS4_TOOLCHAIN}/lib/libunwind.a ${ORBIS_CRT1}")
set(CMAKE_CXX_STANDARD_LIBRARIES "${CMAKE_C_STANDARD_LIBRARIES}")
