#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#define NEED_newCONSTSUB
#define NEED_sv_2pv_flags
#include "ppport.h"

#define MATH_INT64_NATIVE_IF_AVAILABLE
/* define int64_t and uint64_t when using MinGW compiler */
#ifdef __MINGW32__
#include <stdint.h>
#endif

/* define int64_t and uint64_t when using MS compiler */
#ifdef _MSC_VER
#include <stdlib.h>
typedef __int64 int64_t;
typedef unsigned __int64 uint64_t;
#endif

#include "perl_math_int64.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include <uv.h>

struct UVAPI {
    uv_loop_t *default_loop;
};

static struct UVAPI uvapi;
static SV *default_loop_sv;
static HV *stash_loop;

MODULE = UV             PACKAGE = UV            PREFIX = uv_

PROTOTYPES: ENABLE

BOOT:
{
    PERL_MATH_INT64_LOAD_OR_CROAK;
    HV *stash = gv_stashpvn("UV", 2, TRUE);

    /* expose the different handle type constants */
    newCONSTSUB(stash, "UV_UNKNOWN_HANDLE", newSViv(UV_UNKNOWN_HANDLE));
    newCONSTSUB(stash, "UV_ASYNC", newSViv(UV_ASYNC));
    newCONSTSUB(stash, "UV_CHECK", newSViv(UV_CHECK));
    newCONSTSUB(stash, "UV_FS_EVENT", newSViv(UV_FS_EVENT));
    newCONSTSUB(stash, "UV_FS_POLL", newSViv(UV_FS_POLL));
    newCONSTSUB(stash, "UV_HANDLE", newSViv(UV_HANDLE));
    newCONSTSUB(stash, "UV_IDLE", newSViv(UV_IDLE));
    newCONSTSUB(stash, "UV_NAMED_PIPE", newSViv(UV_NAMED_PIPE));
    newCONSTSUB(stash, "UV_POLL", newSViv(UV_POLL));
    newCONSTSUB(stash, "UV_PREPARE", newSViv(UV_PREPARE));
    newCONSTSUB(stash, "UV_PROCESS", newSViv(UV_PROCESS));
    newCONSTSUB(stash, "UV_STREAM", newSViv(UV_STREAM));
    newCONSTSUB(stash, "UV_TCP", newSViv(UV_TCP));
    newCONSTSUB(stash, "UV_TIMER", newSViv(UV_TIMER));
    newCONSTSUB(stash, "UV_TTY", newSViv(UV_TTY));
    newCONSTSUB(stash, "UV_UDP", newSViv(UV_UDP));
    newCONSTSUB(stash, "UV_SIGNAL", newSViv(UV_SIGNAL));
    newCONSTSUB(stash, "UV_FILE", newSViv(UV_FILE));
    newCONSTSUB(stash, "UV_HANDLE_TYPE_MAX", newSViv(UV_HANDLE_TYPE_MAX));
}

uint64_t uv_hrtime()

MODULE = UV             PACKAGE = UV::Loop      PREFIX = uv_

PROTOTYPES: DISABLE

SV *new (SV *klass, int want_default = 0)
    ALIAS:
            UV::Loop::default_loop = 1
    CODE:
{
    uv_loop_t *loop;
    int ret;
    if (ix == 1) want_default = 1;
    warn("Current value of want_default: %i", want_default);
    if (0 == want_default) {
        Newx(loop, 1, uv_loop_t);
        if (NULL == loop) {
            croak("Unable to allocate space for a new loop");
            XSRETURN_UNDEF;
        }
        ret = uv_loop_init(loop);
        if (0 == ret) {
            RETVAL = sv_bless (newRV_noinc (newSViv (PTR2IV (loop))), stash_loop);
        }
        else {
            Safefree(loop);
            croak("Error initializing loop (%i): %s", ret, uv_strerror(ret));
            XSRETURN_UNDEF;
        }
    }
    else {
        warn("Starting to create a new default loop");
        if (!default_loop_sv) {
            warn("We don't yet have one, so let's get the default loop");
            uvapi.default_loop = uv_default_loop();
            warn("Got it");
            if (!uvapi.default_loop) {
                croak("Error getting a new default loop");
                XSRETURN_UNDEF;
            }
            warn("save the default loop as a blessed sv ref");
            default_loop_sv = sv_bless (newRV_noinc (newSViv (PTR2IV (uvapi.default_loop))), stash_loop);
            warn("Saved");
        }
        warn("Return a newSVsv of the default loop");
        RETVAL = newSVsv (default_loop_sv);
    }
}
    OUTPUT:
    RETVAL

void DESTROY (uv_loop_t *loop)
    CODE:
    warn("Destroying a loop");
    /* 1. the default loop shouldn't be freed by destroying it's perl loop object */
    /* 2. not doing so helps avoid many global destruction bugs in perl, too */
    if (0 == uv_loop_close(loop)) {
        Safefree(loop);
    }
