#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#define NEED_newCONSTSUB
#define NEED_sv_2pv_flags
#include "ppport.h"

#define MATH_INT64_NATIVE_IF_AVAILABLE
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

BOOT:
{
    HV *stash = gv_stashpvn("UV::Loop", 8, TRUE);
    stash_loop = gv_stashpv("UV::Loop", TRUE);
    newCONSTSUB(stash, "UV_RUN_DEFAULT", newSViv(UV_RUN_DEFAULT));
    newCONSTSUB(stash, "UV_RUN_ONCE", newSViv(UV_RUN_ONCE));
    newCONSTSUB(stash, "UV_RUN_NOWAIT", newSViv(UV_RUN_NOWAIT));
}

SV *new (SV *klass, int want_default = 0)
    ALIAS:
        UV::Loop::default_loop = 1
    CODE:
{
    uv_loop_t *loop;
    int ret;
    if (ix == 1) want_default = 1;
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
        if (!default_loop_sv) {
            uvapi.default_loop = uv_default_loop();
            if (!uvapi.default_loop) {
                croak("Error getting a new default loop");
                XSRETURN_UNDEF;
            }
            default_loop_sv = sv_bless(
                newRV_noinc(newSViv(PTR2IV(uvapi.default_loop))),
                stash_loop
            );
        }
        RETVAL = newSVsv(default_loop_sv);
    }
}
    OUTPUT:
    RETVAL

void DESTROY (uv_loop_t *loop)
    CODE:
    /* 1. the default loop shouldn't be freed by destroying it's perl loop object */
    /* 2. not doing so helps avoid many global destruction bugs in perl, too */
    if (loop == uvapi.default_loop) {
        SvREFCNT_dec (default_loop_sv);
        if (PL_dirty) {
            uv_loop_close((uv_loop_t *) default_loop_sv);
            default_loop_sv = NULL;
        }
    }
    else {
        if (0 == uv_loop_close(loop)) {
            Safefree(loop);
        }
    }

int uv_backend_fd(const uv_loop_t* loop)

int uv_backend_timeout(const uv_loop_t* loop)

int uv_loop_alive(const uv_loop_t* loop)
ALIAS:
    UV::Loop::alive = 1

uint64_t uv_now(const uv_loop_t* loop)

int uv_run(uv_loop_t* loop, uv_run_mode mode=UV_RUN_DEFAULT)

void uv_stop(uv_loop_t* loop)

void uv_update_time(uv_loop_t* loop)
