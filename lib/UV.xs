#define PERL_NO_GET_CONTEXT 1

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define MATH_INT64_NATIVE_IF_AVAILABLE
#include "perl_math_int64.h"
#include <assert.h>
#include <stdlib.h>
#include "xs_object_magic.h"

#include <uv.h>

#if defined(DEBUG) && DEBUG > 0
 #define DEBUG_PRINT(fmt, args...) fprintf(stderr, "C -- %s:%d:%s(): " fmt, \
    __FILE__, __LINE__, __func__, ##args)
#else
 #define DEBUG_PRINT(fmt, args...) /* Don't do anything in release builds */
#endif

#include "p5uv_constants.h"
#include "p5uv_callbacks.h"
#include "p5uv_helpers.h"

#if defined(__MINGW32__) || defined(WIN32)
#include <io.h> /* we need _get_osfhandle() on windows */
#define _MAKE_SOCK(s, f) s = _get_osfhandle(f)
#else
#define _MAKE_SOCK(s,f) s = f
#endif

MODULE = UV             PACKAGE = UV            PREFIX = uv_

PROTOTYPES: ENABLE

BOOT:
{
    HV *stash;
    AV *export;

    PERL_MATH_INT64_LOAD_OR_CROAK;
#define DO_CONST_IV(c) \
    newCONSTSUB_flags(stash, #c, strlen(#c), 0, newSViv(c)); \
    av_push(export, newSVpvs(#c));
#define DO_CONST_PV(c) \
    newCONSTSUB_flags(stash, #c, strlen(#c), 0, newSVpvn(c, strlen(c))); \
    av_push(export, newSVpvs(#c));

    /* constants under UV */
    {
        stash = gv_stashpv("UV", GV_ADD);
        export = get_av("UV::EXPORT_XS", TRUE);

        DO_CONST_IV(UV_VERSION_MAJOR);
        DO_CONST_IV(UV_VERSION_MINOR);
        DO_CONST_IV(UV_VERSION_PATCH);
        DO_CONST_IV(UV_VERSION_IS_RELEASE);
        DO_CONST_IV(UV_VERSION_HEX);
        DO_CONST_PV(UV_VERSION_SUFFIX);

        DO_CONST_IV(UV_E2BIG);
        DO_CONST_IV(UV_EACCES);
        DO_CONST_IV(UV_EADDRINUSE);
        DO_CONST_IV(UV_EADDRNOTAVAIL);
        DO_CONST_IV(UV_EAFNOSUPPORT);
        DO_CONST_IV(UV_EAGAIN);
        DO_CONST_IV(UV_EAI_ADDRFAMILY);
        DO_CONST_IV(UV_EAI_AGAIN);
        DO_CONST_IV(UV_EAI_BADFLAGS);
        DO_CONST_IV(UV_EAI_BADHINTS);
        DO_CONST_IV(UV_EAI_CANCELED);
        DO_CONST_IV(UV_EAI_FAIL);
        DO_CONST_IV(UV_EAI_FAMILY);
        DO_CONST_IV(UV_EAI_MEMORY);
        DO_CONST_IV(UV_EAI_NODATA);
        DO_CONST_IV(UV_EAI_NONAME);
        DO_CONST_IV(UV_EAI_OVERFLOW);
        DO_CONST_IV(UV_EAI_PROTOCOL);
        DO_CONST_IV(UV_EAI_SERVICE);
        DO_CONST_IV(UV_EAI_SOCKTYPE);
        DO_CONST_IV(UV_EALREADY);
        DO_CONST_IV(UV_EBADF);
        DO_CONST_IV(UV_EBUSY);
        DO_CONST_IV(UV_ECANCELED);
        DO_CONST_IV(UV_ECHARSET);
        DO_CONST_IV(UV_ECONNABORTED);
        DO_CONST_IV(UV_ECONNREFUSED);
        DO_CONST_IV(UV_ECONNRESET);
        DO_CONST_IV(UV_EDESTADDRREQ);
        DO_CONST_IV(UV_EEXIST);
        DO_CONST_IV(UV_EFAULT);
        DO_CONST_IV(UV_EFBIG);
        DO_CONST_IV(UV_EHOSTUNREACH);
        DO_CONST_IV(UV_EINTR);
        DO_CONST_IV(UV_EINVAL);
        DO_CONST_IV(UV_EIO);
        DO_CONST_IV(UV_EISCONN);
        DO_CONST_IV(UV_EISDIR);
        DO_CONST_IV(UV_ELOOP);
        DO_CONST_IV(UV_EMFILE);
        DO_CONST_IV(UV_EMSGSIZE);
        DO_CONST_IV(UV_ENAMETOOLONG);
        DO_CONST_IV(UV_ENETDOWN);
        DO_CONST_IV(UV_ENETUNREACH);
        DO_CONST_IV(UV_ENFILE);
        DO_CONST_IV(UV_ENOBUFS);
        DO_CONST_IV(UV_ENODEV);
        DO_CONST_IV(UV_ENOENT);
        DO_CONST_IV(UV_ENOMEM);
        DO_CONST_IV(UV_ENONET);
        DO_CONST_IV(UV_ENOPROTOOPT);
        DO_CONST_IV(UV_ENOSPC);
        DO_CONST_IV(UV_ENOSYS);
        DO_CONST_IV(UV_ENOTCONN);
        DO_CONST_IV(UV_ENOTDIR);
        DO_CONST_IV(UV_ENOTEMPTY);
        DO_CONST_IV(UV_ENOTSOCK);
        DO_CONST_IV(UV_ENOTSUP);
        DO_CONST_IV(UV_EPERM);
        DO_CONST_IV(UV_EPIPE);
        DO_CONST_IV(UV_EPROTO);
        DO_CONST_IV(UV_EPROTONOSUPPORT);
        DO_CONST_IV(UV_EPROTOTYPE);
        DO_CONST_IV(UV_ERANGE);
        DO_CONST_IV(UV_EROFS);
        DO_CONST_IV(UV_ESHUTDOWN);
        DO_CONST_IV(UV_ESPIPE);
        DO_CONST_IV(UV_ESRCH);
        DO_CONST_IV(UV_ETIMEDOUT);
        DO_CONST_IV(UV_ETXTBSY);
        DO_CONST_IV(UV_EXDEV);
        DO_CONST_IV(UV_UNKNOWN);
        DO_CONST_IV(UV_EOF);
        DO_CONST_IV(UV_ENXIO);
        DO_CONST_IV(UV_EMLINK);
    }

    /* constants under UV::Handle */
    {
        stash = gv_stashpv("UV::Handle", GV_ADD);
        export = get_av("UV::Handle::EXPORT_XS", TRUE);

        DO_CONST_IV(UV_ASYNC);
        DO_CONST_IV(UV_CHECK);
        DO_CONST_IV(UV_FS_EVENT);
        DO_CONST_IV(UV_FS_POLL);
        DO_CONST_IV(UV_IDLE);
        DO_CONST_IV(UV_NAMED_PIPE);
        DO_CONST_IV(UV_POLL);
        DO_CONST_IV(UV_PREPARE);
        DO_CONST_IV(UV_PROCESS);
        DO_CONST_IV(UV_STREAM);
        DO_CONST_IV(UV_TCP);
        DO_CONST_IV(UV_TIMER);
        DO_CONST_IV(UV_TTY);
        DO_CONST_IV(UV_UDP);
        DO_CONST_IV(UV_SIGNAL);
        DO_CONST_IV(UV_FILE);
    }

    /* constants under UV::Loop */
    {
        stash = gv_stashpv("UV::Loop", GV_ADD);
        export = get_av("UV::Loop::EXPORT_XS", TRUE);

        /* Loop run constants */
        DO_CONST_IV(UV_RUN_DEFAULT);
        DO_CONST_IV(UV_RUN_ONCE);
        DO_CONST_IV(UV_RUN_NOWAIT);

        /* expose the Loop configure constants */
        DO_CONST_IV(UV_LOOP_BLOCK_SIGNAL);
        DO_CONST_IV(SIGPROF);
    }

    /* constants under UV::Poll */
    {
        stash = gv_stashpv("UV::Poll", GV_ADD);
        export = get_av("UV::Poll::EXPORT_XS", TRUE);

        /* Poll Event Types */
        DO_CONST_IV(UV_READABLE);
        DO_CONST_IV(UV_WRITABLE);
        DO_CONST_IV(UV_DISCONNECT);
        DO_CONST_IV(UV_PRIORITIZED);
    }
}

const char* uv_err_name(int err)

uint64_t uv_hrtime()

const char* uv_strerror(int err)

unsigned int uv_version()

const char* uv_version_string()

INCLUDE: handle.xsi

INCLUDE: check.xsi

INCLUDE: idle.xsi

INCLUDE: poll.xsi

INCLUDE: prepare.xsi

INCLUDE: timer.xsi

INCLUDE: loop.xsi
