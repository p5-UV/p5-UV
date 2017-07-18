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
    SV *check_cb;
    SV *close_cb;
    SV *idle_cb;
    SV *prepare_cb;
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

/* Handle function definitions for some that aren't alpha ordered later */
static void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf);
static SV * handle_bless(uv_handle_t *h);
static void handle_check_cb(uv_check_t* handle);
static void handle_close_cb(uv_handle_t* handle);
static HV * handle_data_stash(const uv_handle_type type);
static void handle_idle_cb(uv_idle_t* handle);
static void handle_prepare_cb(uv_prepare_t* handle);
static void handle_timer_cb(uv_timer_t* handle);
static void loop_walk_cb(uv_handle_t* handle, void* arg);

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

static void loop_walk_cb(uv_handle_t* handle, void* arg)
{
    SV *callback;
    if (NULL == arg || (SV *)arg == &PL_sv_undef) return;
    callback = arg ? s_get_cv_croak((SV *)arg) : NULL;
    if (NULL == callback) return;

    /* provide info to the caller: invocant, suggested_size */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK (SP);
    EXTEND (SP, 1);
    PUSHs(handle_bless(handle)); /* invocant */

    PUTBACK;
    call_sv (callback, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
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
    if (NULL != data_ptr->check_cb) {
        SvREFCNT_dec(data_ptr->check_cb);
        data_ptr->check_cb = NULL;
    }
    if (NULL != data_ptr->close_cb) {
        SvREFCNT_dec(data_ptr->close_cb);
        data_ptr->close_cb = NULL;
    }
    if (NULL != data_ptr->idle_cb) {
        SvREFCNT_dec(data_ptr->idle_cb);
        data_ptr->idle_cb = NULL;
    }
    if (NULL != data_ptr->prepare_cb) {
        SvREFCNT_dec(data_ptr->prepare_cb);
        data_ptr->prepare_cb = NULL;
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

    /* set the stash */
    data_ptr->stash = handle_data_stash(type);
    if (NULL == data_ptr->stash) {
        free(data_ptr);
        croak("Invalid handle type supplied (%i)", type);
    }

    /* setup the user data */
    data_ptr->user_data = NULL;

    /* setup the loop_sv slot */
    data_ptr->loop_sv = NULL;

    /* setup the callback slots */
    data_ptr->alloc_cb = NULL;
    data_ptr->check_cb = NULL;
    data_ptr->close_cb = NULL;
    data_ptr->idle_cb = NULL;
    data_ptr->prepare_cb = NULL;
    data_ptr->timer_cb = NULL;
    return data_ptr;
}

static HV * handle_data_stash(const uv_handle_type type)
{
    if (type == UV_ASYNC) return stash_async;
    if (type == UV_CHECK) return stash_check;
    if (type == UV_FS_EVENT) return stash_check;
    if (type == UV_FS_POLL) return stash_fs_poll;
    if (type == UV_IDLE) return stash_idle;
    if (type == UV_NAMED_PIPE) return stash_named_pipe;
    if (type == UV_POLL) return stash_poll;
    if (type == UV_PREPARE) return stash_prepare;
    if (type == UV_PROCESS) return stash_process;
    if (type == UV_STREAM) return stash_stream;
    if (type == UV_TCP) return stash_tcp;
    if (type == UV_TIMER) return stash_timer;
    if (type == UV_TTY) return stash_tty;
    if (type == UV_UDP) return stash_udp;
    if (type == UV_SIGNAL) return stash_signal;
    if (type == UV_FILE) return stash_file;
    return NULL;
}

static void handle_destroy(uv_handle_t *handle)
{
    if (NULL == handle) return;
    if (0 == uv_is_closing(handle) && 0 == uv_is_active(handle)) {
        uv_close(handle, handle_close_cb);
        handle_data_destroy(uv_data(handle));
        /*Safefree(handle);*/
    }
}

static uv_handle_t* handle_new(const uv_handle_type type)
{
    uv_handle_t *handle;
    SV *self;
    handle_data_t *data_ptr = handle_data_new(type);
    size_t size = uv_handle_size(type);

    self = NEWSV(0, size);
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
    handle_data_t *data_ptr = uv_data(handle);
    if (!data_ptr) return;

    callback = cb ? s_get_cv_croak(cb) : NULL;

    /* find out which callback to set */
    if (strEQ(name, "alloc")) {
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
    else if (strEQ(name, "check")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->check_cb) {
            SvREFCNT_dec(data_ptr->check_cb);
            data_ptr->check_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->check_cb = SvREFCNT_inc(callback);
        }
    }
    else if (strEQ(name, "close")) {
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
    else if (strEQ(name, "idle")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->idle_cb) {
            SvREFCNT_dec(data_ptr->idle_cb);
            data_ptr->idle_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->idle_cb = SvREFCNT_inc(callback);
        }
    }
    else if (strEQ(name, "prepare")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->prepare_cb) {
            SvREFCNT_dec(data_ptr->prepare_cb);
            data_ptr->prepare_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->prepare_cb = SvREFCNT_inc(callback);
        }
    }
    else if (strEQ(name, "timer")) {
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
    mPUSHi(suggested_size);

    PUTBACK;
    call_sv (data_ptr->alloc_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

static void handle_check_cb(uv_check_t* handle)
{
    handle_data_t *data_ptr = uv_data(handle);

    /* call the close_cb if we have one */
    if (NULL != data_ptr && NULL != data_ptr->check_cb) {
        /* provide info to the caller: invocant */
        dSP;
        ENTER;
        SAVETMPS;

        PUSHMARK (SP);
        EXTEND (SP, 1);
        PUSHs(handle_bless((uv_handle_t *)handle)); /* invocant */

        PUTBACK;
        call_sv (data_ptr->check_cb, G_VOID);
        SPAGAIN;

        FREETMPS;
        LEAVE;
    }
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
}

static void handle_idle_cb(uv_idle_t* handle)
{
    handle_data_t *data_ptr = uv_data(handle);
    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->idle_cb) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK (SP);
    EXTEND (SP, 1);
    PUSHs(handle_bless((uv_handle_t *) handle)); /* invocant */

    PUTBACK;
    call_sv (data_ptr->idle_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

static void handle_prepare_cb(uv_prepare_t* handle)
{
    handle_data_t *data_ptr = uv_data(handle);
    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->prepare_cb) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK (SP);
    EXTEND (SP, 1);
    PUSHs(handle_bless((uv_handle_t *) handle)); /* invocant */

    PUTBACK;
    call_sv (data_ptr->prepare_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
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
    /* grab the PACKAGE hash. If it doesn't yet exist, create it */
    HV *stash = gv_stashpv("UV", GV_ADD);

    /* add some constants to the package stash */
    {
        /* expose the different error constants */
        newCONSTSUB(stash, "UV_E2BIG", newSViv(UV_E2BIG));
        newCONSTSUB(stash, "UV_EACCES", newSViv(UV_EACCES));
        newCONSTSUB(stash, "UV_EADDRINUSE", newSViv(UV_EADDRINUSE));
        newCONSTSUB(stash, "UV_EADDRNOTAVAIL", newSViv(UV_EADDRNOTAVAIL));
        newCONSTSUB(stash, "UV_EAFNOSUPPORT", newSViv(UV_EAFNOSUPPORT));
        newCONSTSUB(stash, "UV_EAGAIN", newSViv(UV_EAGAIN));
        newCONSTSUB(stash, "UV_EAI_ADDRFAMILY", newSViv(UV_EAI_ADDRFAMILY));
        newCONSTSUB(stash, "UV_EAI_AGAIN", newSViv(UV_EAI_AGAIN));
        newCONSTSUB(stash, "UV_EAI_BADFLAGS", newSViv(UV_EAI_BADFLAGS));
        newCONSTSUB(stash, "UV_EAI_BADHINTS", newSViv(UV_EAI_BADHINTS));
        newCONSTSUB(stash, "UV_EAI_CANCELED", newSViv(UV_EAI_CANCELED));
        newCONSTSUB(stash, "UV_EAI_FAIL", newSViv(UV_EAI_FAIL));
        newCONSTSUB(stash, "UV_EAI_FAMILY", newSViv(UV_EAI_FAMILY));
        newCONSTSUB(stash, "UV_EAI_MEMORY", newSViv(UV_EAI_MEMORY));
        newCONSTSUB(stash, "UV_EAI_NODATA", newSViv(UV_EAI_NODATA));
        newCONSTSUB(stash, "UV_EAI_NONAME", newSViv(UV_EAI_NONAME));
        newCONSTSUB(stash, "UV_EAI_OVERFLOW", newSViv(UV_EAI_OVERFLOW));
        newCONSTSUB(stash, "UV_EAI_PROTOCOL", newSViv(UV_EAI_PROTOCOL));
        newCONSTSUB(stash, "UV_EAI_SERVICE", newSViv(UV_EAI_SERVICE));
        newCONSTSUB(stash, "UV_EAI_SOCKTYPE", newSViv(UV_EAI_SOCKTYPE));
        newCONSTSUB(stash, "UV_EALREADY", newSViv(UV_EALREADY));
        newCONSTSUB(stash, "UV_EBADF", newSViv(UV_EBADF));
        newCONSTSUB(stash, "UV_EBUSY", newSViv(UV_EBUSY));
        newCONSTSUB(stash, "UV_ECANCELED", newSViv(UV_ECANCELED));
        newCONSTSUB(stash, "UV_ECHARSET", newSViv(UV_ECHARSET));
        newCONSTSUB(stash, "UV_ECONNABORTED", newSViv(UV_ECONNABORTED));
        newCONSTSUB(stash, "UV_ECONNREFUSED", newSViv(UV_ECONNREFUSED));
        newCONSTSUB(stash, "UV_ECONNRESET", newSViv(UV_ECONNRESET));
        newCONSTSUB(stash, "UV_EDESTADDRREQ", newSViv(UV_EDESTADDRREQ));
        newCONSTSUB(stash, "UV_EEXIST", newSViv(UV_EEXIST));
        newCONSTSUB(stash, "UV_EFAULT", newSViv(UV_EFAULT));
        newCONSTSUB(stash, "UV_EFBIG", newSViv(UV_EFBIG));
        newCONSTSUB(stash, "UV_EHOSTUNREACH", newSViv(UV_EHOSTUNREACH));
        newCONSTSUB(stash, "UV_EINTR", newSViv(UV_EINTR));
        newCONSTSUB(stash, "UV_EINVAL", newSViv(UV_EINVAL));
        newCONSTSUB(stash, "UV_EIO", newSViv(UV_EIO));
        newCONSTSUB(stash, "UV_EISCONN", newSViv(UV_EISCONN));
        newCONSTSUB(stash, "UV_EISDIR", newSViv(UV_EISDIR));
        newCONSTSUB(stash, "UV_ELOOP", newSViv(UV_ELOOP));
        newCONSTSUB(stash, "UV_EMFILE", newSViv(UV_EMFILE));
        newCONSTSUB(stash, "UV_EMSGSIZE", newSViv(UV_EMSGSIZE));
        newCONSTSUB(stash, "UV_ENAMETOOLONG", newSViv(UV_ENAMETOOLONG));
        newCONSTSUB(stash, "UV_ENETDOWN", newSViv(UV_ENETDOWN));
        newCONSTSUB(stash, "UV_ENETUNREACH", newSViv(UV_ENETUNREACH));
        newCONSTSUB(stash, "UV_ENFILE", newSViv(UV_ENFILE));
        newCONSTSUB(stash, "UV_ENOBUFS", newSViv(UV_ENOBUFS));
        newCONSTSUB(stash, "UV_ENODEV", newSViv(UV_ENODEV));
        newCONSTSUB(stash, "UV_ENOENT", newSViv(UV_ENOENT));
        newCONSTSUB(stash, "UV_ENOMEM", newSViv(UV_ENOMEM));
        newCONSTSUB(stash, "UV_ENONET", newSViv(UV_ENONET));
        newCONSTSUB(stash, "UV_ENOPROTOOPT", newSViv(UV_ENOPROTOOPT));
        newCONSTSUB(stash, "UV_ENOSPC", newSViv(UV_ENOSPC));
        newCONSTSUB(stash, "UV_ENOSYS", newSViv(UV_ENOSYS));
        newCONSTSUB(stash, "UV_ENOTCONN", newSViv(UV_ENOTCONN));
        newCONSTSUB(stash, "UV_ENOTDIR", newSViv(UV_ENOTDIR));
        newCONSTSUB(stash, "UV_ENOTEMPTY", newSViv(UV_ENOTEMPTY));
        newCONSTSUB(stash, "UV_ENOTSOCK", newSViv(UV_ENOTSOCK));
        newCONSTSUB(stash, "UV_ENOTSUP", newSViv(UV_ENOTSUP));
        newCONSTSUB(stash, "UV_EPERM", newSViv(UV_EPERM));
        newCONSTSUB(stash, "UV_EPIPE", newSViv(UV_EPIPE));
        newCONSTSUB(stash, "UV_EPROTO", newSViv(UV_EPROTO));
        newCONSTSUB(stash, "UV_EPROTONOSUPPORT", newSViv(UV_EPROTONOSUPPORT));
        newCONSTSUB(stash, "UV_EPROTOTYPE", newSViv(UV_EPROTOTYPE));
        newCONSTSUB(stash, "UV_ERANGE", newSViv(UV_ERANGE));
        newCONSTSUB(stash, "UV_EROFS", newSViv(UV_EROFS));
        newCONSTSUB(stash, "UV_ESHUTDOWN", newSViv(UV_ESHUTDOWN));
        newCONSTSUB(stash, "UV_ESPIPE", newSViv(UV_ESPIPE));
        newCONSTSUB(stash, "UV_ESRCH", newSViv(UV_ESRCH));
        newCONSTSUB(stash, "UV_ETIMEDOUT", newSViv(UV_ETIMEDOUT));
        newCONSTSUB(stash, "UV_ETXTBSY", newSViv(UV_ETXTBSY));
        newCONSTSUB(stash, "UV_EXDEV", newSViv(UV_EXDEV));
        newCONSTSUB(stash, "UV_UNKNOWN", newSViv(UV_UNKNOWN));
        newCONSTSUB(stash, "UV_EOF", newSViv(UV_EOF));
        newCONSTSUB(stash, "UV_ENXIO", newSViv(UV_ENXIO));
        newCONSTSUB(stash, "UV_EMLINK", newSViv(UV_EMLINK));
    }

    /* make sure we have a pointer to our other namespace stashes */
    /* loop stash */
    stash_loop          = gv_stashpv("UV::Loop",        GV_ADD);
    /* handle stashes */
    stash_async         = gv_stashpv("UV::Async",       GV_ADD);
    stash_check         = gv_stashpv("UV::Check",       GV_ADD);
    stash_fs_event      = gv_stashpv("UV::FSEvent",     GV_ADD);
    stash_fs_poll       = gv_stashpv("UV::FSPoll",      GV_ADD);
    stash_handle        = gv_stashpv("UV::Handle",      GV_ADD);
    stash_idle          = gv_stashpv("UV::Idle",        GV_ADD);
    stash_named_pipe    = gv_stashpv("UV::NamedPipe",   GV_ADD);
    stash_poll          = gv_stashpv("UV::Poll",        GV_ADD);
    stash_prepare       = gv_stashpv("UV::Prepare",     GV_ADD);
    stash_process       = gv_stashpv("UV::Process",     GV_ADD);
    stash_stream        = gv_stashpv("UV::Stream",      GV_ADD);
    stash_tcp           = gv_stashpv("UV::TCP",         GV_ADD);
    stash_timer         = gv_stashpv("UV::Timer",       GV_ADD);
    stash_tty           = gv_stashpv("UV::TTY",         GV_ADD);
    stash_udp           = gv_stashpv("UV::UDP",         GV_ADD);
    stash_signal        = gv_stashpv("UV::Signal",      GV_ADD);
    stash_file          = gv_stashpv("UV::File",        GV_ADD);

    /* somewhat of an API */
    uvapi.default_loop = NULL;
}

SV *uv_default_loop()
    CODE:
    loop_default_init();
    RETVAL = newSVsv(default_loop_sv);
    OUTPUT:
    RETVAL

uint64_t uv_hrtime()



MODULE = UV             PACKAGE = UV::Handle      PREFIX = uv_handle_

PROTOTYPES: ENABLE

BOOT:
{
    /* grab the PACKAGE hash. If it doesn't yet exist, create it */
    HV *stash = gv_stashpv("UV::Handle", GV_ADD);

    /* add some constants to the package stash */

    /* expose the different handle type constants */
    newCONSTSUB(stash, "UV_ASYNC", newSViv(UV_ASYNC));
    newCONSTSUB(stash, "UV_CHECK", newSViv(UV_CHECK));
    newCONSTSUB(stash, "UV_FS_EVENT", newSViv(UV_FS_EVENT));
    newCONSTSUB(stash, "UV_FS_POLL", newSViv(UV_FS_POLL));
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
}

void DESTROY(uv_handle_t *handle)
    CODE:
    handle_destroy(handle);

SV *uv_handle_loop(uv_handle_t *handle)
    CODE:
    RETVAL = newSVsv(uv_data(handle)->loop_sv);
    OUTPUT:
    RETVAL

int uv_handle_active (uv_handle_t *handle)
    ALIAS:
        UV::Handle::is_active = 1
    CODE:
        RETVAL = uv_is_active(handle);
    OUTPUT:
    RETVAL

int uv_handle_closing(uv_handle_t *handle)
    ALIAS:
        UV::Handle::is_closing = 1
    CODE:
        RETVAL = uv_is_closing(handle);
    OUTPUT:
    RETVAL

void uv_handle_close(uv_handle_t *handle, SV *cb=NULL)
    CODE:
    if (items > 1) {
        cb = cb == &PL_sv_undef ? NULL : cb;
        handle_on(handle, "close", cb);
    }
    uv_close(handle, handle_close_cb);

SV * uv_handle_data(uv_handle_t *handle, SV *new_val = NULL)
    CODE:
        handle_data_t *data_ptr = uv_data(handle);
        RETVAL = data_ptr->user_data ? newSVsv(data_ptr->user_data) : &PL_sv_undef;
        if (items > 1) {
            if (NULL != data_ptr->user_data) {
                SvREFCNT_dec(data_ptr->user_data);
                data_ptr->user_data = NULL;
            }

            if (new_val != &PL_sv_undef) {
                data_ptr->user_data = newSVsv(new_val);
            }
            /* chainable setter */
            RETVAL = handle_bless(handle);
        }
    OUTPUT:
    RETVAL

int uv_handle_has_ref(uv_handle_t *handle)
    CODE:
        RETVAL = uv_has_ref(handle);
    OUTPUT:
    RETVAL

void uv_handle_on(uv_handle_t *handle, const char *name, SV *cb=NULL)
    CODE:
    cb = cb == &PL_sv_undef ? NULL : cb;
    handle_on(handle, name, cb);

void uv_handle_ref(uv_handle_t *handle)
    CODE:
    uv_ref(handle);

int uv_handle_type(uv_handle_t *handle)
    CODE:
    RETVAL = handle->type;
    OUTPUT:
    RETVAL

void uv_handle_unref(uv_handle_t *handle)
    CODE:
    uv_unref(handle);



MODULE = UV             PACKAGE = UV::Check      PREFIX = uv_check_

PROTOTYPES: ENABLE

SV * uv_check_new(SV *class, uv_loop_t *loop = uvapi.default_loop)
    CODE:
    int res;
    uv_check_t *handle = (uv_check_t *)handle_new(UV_CHECK);
    PERL_UNUSED_VAR(class);
    loop_default_init();
    if (NULL == loop) loop = uvapi.default_loop;


    res = uv_check_init(loop, handle);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize check (%i): %s", res, uv_strerror(res));
    }

    if (loop == uvapi.default_loop) {
        uv_data(handle)->loop_sv = default_loop_sv;
    }
    else {
        uv_data(handle)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), stash_loop);
    }
    RETVAL = handle_bless((uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_check_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_check_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(uv_data(handle));
    }

int uv_check_start(uv_check_t *handle, SV *cb=NULL)
    CODE:
        if (items > 1) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on((uv_handle_t *)handle, "check", cb);
        }
        RETVAL = uv_check_start(handle, handle_check_cb);
    OUTPUT:
    RETVAL

int uv_check_stop(uv_check_t *handle)



MODULE = UV             PACKAGE = UV::Idle      PREFIX = uv_idle_

PROTOTYPES: ENABLE

SV * uv_idle_new(SV *class, uv_loop_t *loop = uvapi.default_loop)
    CODE:
    int res;
    uv_idle_t *handle = (uv_idle_t *)handle_new(UV_IDLE);
    PERL_UNUSED_VAR(class);
    loop_default_init();
    if (NULL == loop) loop = uvapi.default_loop;


    res = uv_idle_init(loop, handle);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize idle (%i): %s", res, uv_strerror(res));
    }

    if (loop == uvapi.default_loop) {
        uv_data(handle)->loop_sv = default_loop_sv;
    }
    else {
        uv_data(handle)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), stash_loop);
    }
    RETVAL = handle_bless((uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_idle_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_idle_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(uv_data(handle));
    }

int uv_idle_start(uv_idle_t *handle, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 1) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on((uv_handle_t *)handle, "idle", cb);
        }
        RETVAL = uv_idle_start(handle, handle_idle_cb);
    OUTPUT:
    RETVAL

int uv_idle_stop(uv_idle_t *handle)



MODULE = UV             PACKAGE = UV::Prepare      PREFIX = uv_prepare_

PROTOTYPES: ENABLE

SV * uv_prepare_new(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_prepare_t *prepare = (uv_prepare_t *)handle_new(UV_PREPARE);
    PERL_UNUSED_VAR(class);
    loop_default_init();
    if (NULL == loop) loop = uvapi.default_loop;

    res = uv_prepare_init(loop, prepare);
    if (0 != res) {
        Safefree(prepare);
        croak("Couldn't initialize prepare (%i): %s", res, uv_strerror(res));
    }

    if (loop == uvapi.default_loop) {
        uv_data(prepare)->loop_sv = default_loop_sv;
    }
    else {
        uv_data(prepare)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), stash_loop);
    }
    RETVAL = handle_bless((uv_handle_t *)prepare);
    OUTPUT:
    RETVAL

void DESTROY(uv_prepare_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_prepare_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(uv_data(handle));
    }

int uv_prepare_start(uv_prepare_t *handle, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 1) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on((uv_handle_t *)handle, "prepare", cb);
        }
        RETVAL = uv_prepare_start(handle, handle_prepare_cb);
    OUTPUT:
    RETVAL

int uv_prepare_stop(uv_prepare_t *handle)



MODULE = UV             PACKAGE = UV::Timer      PREFIX = uv_timer_

PROTOTYPES: ENABLE

SV * uv_timer_new(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_timer_t *timer = (uv_timer_t *)handle_new(UV_TIMER);
    PERL_UNUSED_VAR(class);
    loop_default_init();
    if (NULL == loop) loop = uvapi.default_loop;

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
    OUTPUT:
    RETVAL

void DESTROY(uv_timer_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_timer_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(uv_data(handle));
    }

int uv_timer_again(uv_timer_t *handle)

int uv_timer_start(uv_timer_t *handle, uint64_t start=0, uint64_t repeat=0, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 3) {
            cb = cb == &PL_sv_undef ? NULL : cb;
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

void uv_timer_set_repeat(uv_timer_t *handle, uint64_t repeat)


MODULE = UV             PACKAGE = UV::Loop      PREFIX = uv_

PROTOTYPES: ENABLE

BOOT:
{
    HV *stash = gv_stashpvn("UV::Loop", 8, TRUE);
    /* Loop run constants */
    newCONSTSUB(stash, "UV_RUN_DEFAULT", newSViv(UV_RUN_DEFAULT));
    newCONSTSUB(stash, "UV_RUN_ONCE", newSViv(UV_RUN_ONCE));
    newCONSTSUB(stash, "UV_RUN_NOWAIT", newSViv(UV_RUN_NOWAIT));
    /* expose the Loop configure constants */
    newCONSTSUB(stash, "UV_LOOP_BLOCK_SIGNAL", newSViv(UV_LOOP_BLOCK_SIGNAL));
    newCONSTSUB(stash, "SIGPROF", newSViv(SIGPROF));
}

SV *new (SV *class, int want_default = 0)
    ALIAS:
        UV::Loop::default_loop = 1
        UV::Loop::default = 2
    CODE:
    uv_loop_t *loop;
    PERL_UNUSED_VAR(class);
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
        loop_default_init();
        RETVAL = newSVsv(default_loop_sv);
    }
    OUTPUT:
    RETVAL

void DESTROY (uv_loop_t *loop)
    CODE:
    /* 1. the default loop shouldn't be freed by destroying it's perl loop object */
    /* 2. not doing so helps avoid many global destruction bugs in perl, too */
    if (loop == uvapi.default_loop) {
        SvREFCNT_dec(default_loop_sv);
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

int uv_close(uv_loop_t *loop)
    CODE:
        RETVAL = uv_loop_close(loop);
        if (loop == uvapi.default_loop) {
            SvREFCNT_dec(default_loop_sv);
            default_loop_sv = NULL;
            uvapi.default_loop = NULL;
        }
    OUTPUT:
    RETVAL

int uv_loop_alive(const uv_loop_t* loop)
    ALIAS:
    UV::Loop::alive = 1

int uv_loop_configure(uv_loop_t* loop, uv_loop_option option, int value)
    ALIAS:
    UV::Loop::configure = 1

uint64_t uv_now(const uv_loop_t* loop)

int uv_run(uv_loop_t* loop, uv_run_mode mode=UV_RUN_DEFAULT)

void uv_stop(uv_loop_t* loop)

void uv_update_time(uv_loop_t* loop)

void uv_walk(uv_loop_t *loop, SV *cb=NULL)
    CODE:
        cb = cb == &PL_sv_undef ? NULL : cb;
        uv_walk(loop, loop_walk_cb, (void *)cb);
