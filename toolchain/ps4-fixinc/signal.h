/* ps4-fixinc: FreeBSD realtime signal range (musl's __libc_current_sigrtmin() reports Linux's 35).
 * The probe delivered signal 65 to a thread with pthread_kill on hardware. */
#ifndef _PS4_FIXINC_SIGNAL_H
#define _PS4_FIXINC_SIGNAL_H
#include_next <signal.h>
#undef SIGRTMIN
#undef SIGRTMAX
#define SIGRTMIN 65
#define SIGRTMAX 126
#endif
