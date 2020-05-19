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
    PERL_MATH_INT64_LOAD_OR_CROAK;
    constants_export_uv(aTHX);
    constants_export_uv_handle(aTHX);
    constants_export_uv_poll(aTHX);
    constants_export_uv_loop(aTHX);
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
