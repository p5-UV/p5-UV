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

#define uv_loop(h)      INT2PTR (uv_loop_t *, SvIVX (((uv_handle_t *)(h))->loop))
#define uv_data(h)      ((handle_data_t *)((uv_handle_t *)(h))->data)
#define uv_user_data(h) uv_data(h)->user_data;

struct UVAPI {
    uv_loop_t *default_loop;
};

/* data to store with a HANDLE */
typedef struct handle_data_s {
    SV *self;
    SV *loop_sv;
    HV *stash;
    SV *user_data;
    /* callbacks available */
    SV *alloc_cb;
    SV *close_cb;
    SV *timer_cb;
} handle_data_t;

static struct UVAPI uvapi;
static SV *default_loop_sv;
static HV *stash_loop;

/* handle stashes */
static HV
    *stash_async,
    *stash_check,
    *stash_fs_event,
    *stash_fs_poll,
    *stash_handle,
    *stash_idle,
    *stash_named_pipe,
    *stash_poll,
    *stash_prepare,
    *stash_process,
    *stash_stream,
    *stash_tcp,
    *stash_timer,
    *stash_tty,
    *stash_udp,
    *stash_signal,
    *stash_file;

static SV * s_get_cv (SV *cb_sv)
{
    dTHX;
    HV *st;
    GV *gvp;

    return (SV *)sv_2cv(cb_sv, &st, &gvp, 0);
}

static SV * s_get_cv_croak (SV *cb_sv)
{
    SV *cv = s_get_cv(cb_sv);

    if (!cv) {
        dTHX;
        croak("%s: callback must be a CODE reference or another callable object", SvPV_nolen(cb_sv));
    }

    return cv;
}

/* loop functions */
static void loop_default_init()
{
    if (!default_loop_sv) {
        uvapi.default_loop = uv_default_loop();
        if (!uvapi.default_loop) {
            croak("Error getting a new default loop");
        }
        default_loop_sv = sv_bless(
            newRV_noinc(newSViv(PTR2IV(uvapi.default_loop))),
            stash_loop
        );
    }
}

static uv_loop_t * loop_new()
{
    uv_loop_t *loop;
    int ret;
    Newx(loop, 1, uv_loop_t);
    if (NULL == loop) {
        croak("Unable to allocate space for a new loop");
    }
    ret = uv_loop_init(loop);
    if (0 != ret) {
        Safefree(loop);
        croak("Error initializing loop (%i): %s", ret, uv_strerror(ret));
    }
    return loop;
}

/* handle functions */
static SV * handle_bless(uv_handle_t *h)
{
    SV *rv;
    handle_data_t *data_ptr = h->data;

    if (SvOBJECT(data_ptr->self)) {
        rv = newRV_inc(data_ptr->self);
    }
    else {
        rv = newRV_noinc(data_ptr->self);
        sv_bless(rv, data_ptr->stash);
        SvREADONLY_on(data_ptr->self);
    }
    return rv;
}

static void handle_data_destroy(handle_data_t *data_ptr)
{
    if (NULL == data_ptr) return;

    /* cleanup self, loop_sv, user_data, and stash */
    if (NULL != data_ptr->self) {
        data_ptr->self = NULL;
    }
    if (NULL != data_ptr->stash) {
        SvREFCNT_dec(data_ptr->stash);
        data_ptr->stash = NULL;
    }

    /* cleanup any callback references */
    if (NULL != data_ptr->alloc_cb) {
        SvREFCNT_dec(data_ptr->alloc_cb);
        data_ptr->alloc_cb = NULL;
    }
    if (NULL != data_ptr->close_cb) {
        SvREFCNT_dec(data_ptr->close_cb);
        data_ptr->close_cb = NULL;
    }
    if (NULL != data_ptr->timer_cb) {
        SvREFCNT_dec(data_ptr->timer_cb);
        data_ptr->timer_cb = NULL;
    }
    Safefree(data_ptr);
    data_ptr = NULL;
}

static handle_data_t* handle_data_new(const uv_handle_type type)
{
    handle_data_t *data_ptr = (handle_data_t *)malloc(sizeof(handle_data_t));
    if (NULL == data_ptr) {
        croak("Cannot allocate space for handle data.");
    }

    /* set the stash location */
    data_ptr->stash = NULL;
    if (type == UV_ASYNC) data_ptr->stash = stash_async;
    if (type == UV_CHECK) data_ptr->stash = stash_check;
    if (type == UV_FS_EVENT) data_ptr->stash = stash_fs_event;
    if (type == UV_FS_POLL) data_ptr->stash = stash_fs_poll;
    if (type == UV_HANDLE) data_ptr->stash = stash_handle;
    if (type == UV_IDLE) data_ptr->stash = stash_idle;
    if (type == UV_NAMED_PIPE) data_ptr->stash = stash_named_pipe;
    if (type == UV_POLL) data_ptr->stash = stash_poll;
    if (type == UV_PREPARE) data_ptr->stash = stash_prepare;
    if (type == UV_PROCESS) data_ptr->stash = stash_process;
    if (type == UV_STREAM) data_ptr->stash = stash_stream;
    if (type == UV_TCP) data_ptr->stash = stash_tcp;
    if (type == UV_TIMER) data_ptr->stash = stash_timer;
    if (type == UV_TTY) data_ptr->stash = stash_tty;
    if (type == UV_UDP) data_ptr->stash = stash_udp;
    if (type == UV_SIGNAL) data_ptr->stash = stash_signal;
    if (type == UV_FILE) data_ptr->stash = stash_file;
    if (NULL == data_ptr->stash) {
        free(data_ptr);
        croak("Invalid Handle type supplied");
    }

    /* setup the loop_sv slot */
    data_ptr->loop_sv = NULL;

    /* setup the callback slots */
    data_ptr->alloc_cb = NULL;
    data_ptr->close_cb = NULL;
    data_ptr->timer_cb = NULL;
    return data_ptr;
}

static uv_handle_t* handle_new(const uv_handle_type type)
{
    uv_handle_t *handle;
    SV *self;
    handle_data_t *data_ptr = handle_data_new(type);
    size_t size = uv_handle_size(type);

    self = NEWSV (0, size);
    SvPOK_only(self);
    SvCUR_set(self, size);
    handle = (uv_handle_t *) SvPVX(self);
    if (NULL == handle) {
        Safefree(self);
        croak("Cannot allocate space for a new uv_handle_t");
    }

    /* add some data to our new handle */
    data_ptr->self = self;
    handle->data = (void *)data_ptr;
    return handle;
}

static void handle_on(uv_handle_t *handle, const char *name, SV *cb)
{
    SV *callback = NULL;
    handle_data_t *data_ptr;

    if (NULL == handle) return;
    data_ptr = uv_data(handle);
    if (NULL == data_ptr) return;

    callback = cb ? s_get_cv_croak(cb) : NULL;

    /* find out which callback to set */
    if (0 == strcmp(name, "alloc")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->alloc_cb) {
            SvREFCNT_dec(data_ptr->alloc_cb);
            data_ptr->alloc_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->alloc_cb = SvREFCNT_inc(callback);
        }
    }
    else if (0 == strcmp(name, "close")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->close_cb) {
            SvREFCNT_dec(data_ptr->close_cb);
            data_ptr->close_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->close_cb = SvREFCNT_inc(callback);
        }
    }
    else if (0 == strcmp(name, "timer")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->timer_cb) {
            SvREFCNT_dec(data_ptr->timer_cb);
            data_ptr->timer_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->timer_cb = SvREFCNT_inc(callback);
        }
    }
    else {
        croak("Invalid event name (%s)", name);
    }
}

/* HANDLE callbacks */
static void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf)
{
    handle_data_t *data_ptr = uv_data(handle);
    buf->base = malloc(suggested_size);
    buf->len = suggested_size;

    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->alloc_cb) return;

    /* provide info to the caller: invocant, suggested_size */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK (SP);
    EXTEND (SP, 2);
    PUSHs(handle_bless(handle)); /* invocant */
    PUSHs(newSViv(suggested_size));

    PUTBACK;
    call_sv (data_ptr->alloc_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

static void handle_close_cb(uv_handle_t* handle)
{
    handle_data_t *data_ptr = uv_data(handle);

    /* call the close_cb if we have one */
    if (NULL != data_ptr && NULL != data_ptr->close_cb) {
        /* provide info to the caller: invocant */
        dSP;
        ENTER;
        SAVETMPS;

        PUSHMARK (SP);
        EXTEND (SP, 1);
        PUSHs(handle_bless(handle)); /* invocant */

        PUTBACK;
        call_sv (data_ptr->close_cb, G_VOID);
        SPAGAIN;

        FREETMPS;
        LEAVE;
    }
    handle_data_destroy(data_ptr);
    Safefree(handle);
}

static void handle_timer_cb(uv_timer_t* handle)
{
    handle_data_t *data_ptr = uv_data(handle);
    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->timer_cb) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK (SP);
    EXTEND (SP, 1);
    PUSHs(handle_bless((uv_handle_t *) handle)); /* invocant */

    PUTBACK;
    call_sv (data_ptr->timer_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

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

    /* build out our stashes */
    stash_loop          = gv_stashpv("UV::Loop",        TRUE);

    stash_async         = gv_stashpv("UV::Async",       TRUE);
    stash_check         = gv_stashpv("UV::Check",       TRUE);
    stash_fs_event      = gv_stashpv("UV::FSEvent",     TRUE);
    stash_fs_poll       = gv_stashpv("UV::FSPoll",      TRUE);
    stash_handle        = gv_stashpv("UV::Handle",      TRUE);
    stash_idle          = gv_stashpv("UV::Idle",        TRUE);
    stash_named_pipe    = gv_stashpv("UV::NamedPipe",   TRUE);
    stash_poll          = gv_stashpv("UV::Poll",        TRUE);
    stash_prepare       = gv_stashpv("UV::Prepare",     TRUE);
    stash_process       = gv_stashpv("UV::Process",     TRUE);
    stash_stream        = gv_stashpv("UV::Stream",      TRUE);
    stash_tcp           = gv_stashpv("UV::TCP",         TRUE);
    stash_timer         = gv_stashpv("UV::Timer",       TRUE);
    stash_tty           = gv_stashpv("UV::TTY",         TRUE);
    stash_udp           = gv_stashpv("UV::UDP",         TRUE);
    stash_signal        = gv_stashpv("UV::Signal",      TRUE);
    stash_file          = gv_stashpv("UV::File",        TRUE);

    {
        SV *sv = perl_get_sv("EV::API", TRUE);
        uvapi.default_loop = NULL;
        sv_setiv (sv, (IV)&uvapi);
        SvREADONLY_on (sv);
    }
}


SV *uv_default_loop()
    CODE:
{
    loop_default_init();
    RETVAL = newSVsv(default_loop_sv);
}
    OUTPUT:
    RETVAL

uint64_t uv_hrtime()

MODULE = UV             PACKAGE = UV::Handle      PREFIX = uv_handle_

PROTOTYPES: ENABLE

BOOT:
{
    HV *stash = gv_stashpvn("UV::Handle", 10, TRUE);
}

void DESTROY (uv_handle_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing(handle) && 0 == uv_is_active(handle)) {
        uv_close(handle, handle_close_cb);
    }

SV *uv_handle_loop(uv_handle_t *handle)
    CODE:
{
    RETVAL = newSVsv(uv_data(handle)->loop_sv);
}
    OUTPUT:
    RETVAL

void uv_handle_close(uv_handle_t *handle, SV *cb=NULL)
    CODE:
    if (NULL != cb) {
        handle_on(handle, "close", cb);
    }
    uv_close(handle, handle_close_cb);

void uv_handle_on(uv_handle_t *handle, const char *name, SV *cb=NULL)
    CODE:
    handle_on(handle, name, cb);

MODULE = UV             PACKAGE = UV::Timer      PREFIX = uv_timer_

PROTOTYPES: ENABLE

BOOT:
{
    HV *stash = gv_stashpvn("UV::Timer", 9, TRUE);
}

SV * uv_timer_new(SV *klass, uv_loop_t *loop = uvapi.default_loop)
    CODE:
{
    int res;
    uv_timer_t *timer = (uv_timer_t *)handle_new(UV_TIMER);
    res = uv_timer_init(loop, timer);
    if (0 != res) {
        Safefree(timer);
        croak("Couldn't initialize timer (%i): %s", res, uv_strerror(res));
    }

    if (loop == uvapi.default_loop) {
        uv_data(timer)->loop_sv = default_loop_sv;
    }
    else {
        uv_data(timer)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), stash_loop);
    }
    RETVAL = handle_bless((uv_handle_t *)timer);
}
    OUTPUT:
    RETVAL

int uv_timer_start(uv_timer_t *handle, uint64_t start=0, uint64_t repeat=0, SV *cb=NULL)
    CODE:
        if (NULL != cb) {
            handle_on((uv_handle_t *)handle, "timer", cb);
        }
        RETVAL = uv_timer_start(handle, handle_timer_cb, start, repeat);
    OUTPUT:
    RETVAL

int uv_timer_stop(uv_timer_t *handle)
    CODE:
        RETVAL = uv_timer_stop(handle);
    OUTPUT:
    RETVAL

uint64_t uv_timer_get_repeat(uv_timer_t* handle)
    CODE:
        RETVAL = uv_timer_get_repeat(handle);
    OUTPUT:
    RETVAL

MODULE = UV             PACKAGE = UV::Loop      PREFIX = uv_

PROTOTYPES: ENABLE

BOOT:
{
    HV *stash = gv_stashpvn("UV::Loop", 8, TRUE);
    newCONSTSUB(stash, "UV_RUN_DEFAULT", newSViv(UV_RUN_DEFAULT));
    newCONSTSUB(stash, "UV_RUN_ONCE", newSViv(UV_RUN_ONCE));
    newCONSTSUB(stash, "UV_RUN_NOWAIT", newSViv(UV_RUN_NOWAIT));
}

SV *new (SV *klass, int want_default = 0)
    ALIAS:
        UV::Loop::default_loop = 1
        UV::Loop::default = 2
    CODE:
{
    uv_loop_t *loop;
    if (ix == 1 || ix == 2) want_default = 1;
    if (0 == want_default) {
        loop = loop_new();
        RETVAL = sv_bless(
            newRV_noinc(
                newSViv(
                    PTR2IV(loop)
                )
            ), stash_loop
        );
    }
    else {
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
