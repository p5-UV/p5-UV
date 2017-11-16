#if !defined (P5UV_HANDLES_H)
#define P5UV_HANDLES_H

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"
#include <uv.h>
#include "p5uv_loops.h"

#define handle_data(h)      ((handle_data_t *)((uv_handle_t *)(h))->data)

static SV * handle_get_cv_croak(SV *cb_sv)
{
    dTHX;
    HV *st;
    GV *gvp;
    SV *cv = (SV *)sv_2cv(cb_sv, &st, &gvp, 0);

    if (!cv) {
        dTHX;
        croak("%s: callback must be a CODE reference or another callable object", SvPV_nolen(cb_sv));
    }

    return cv;
}


/* data to store with a HANDLE */
typedef struct handle_data_s {
    SV *self;
    HV *stash;
    SV *user_data;
    /* callbacks available */
    SV *alloc_cb;
    SV *check_cb;
    SV *close_cb;
    SV *idle_cb;
    SV *poll_cb;
    SV *prepare_cb;
    SV *timer_cb;
} handle_data_t;

/* Handle function definitions */
extern void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf);
extern SV * handle_bless(pTHX_ uv_handle_t *h);
extern void handle_check_cb(uv_check_t* handle);
extern void handle_close_cb(uv_handle_t* handle);
extern void handle_data_destroy(pTHX_ handle_data_t *data_ptr);
extern handle_data_t* handle_data_new(pTHX_ const uv_handle_type type);
extern void handle_idle_cb(uv_idle_t* handle);
extern const char* handle_namespace(pTHX_ const uv_handle_type type);
extern uv_handle_t* handle_new(pTHX_ const uv_handle_type type);
extern void handle_on(pTHX_ uv_handle_t *handle, const char *name, SV *cb);
extern void handle_poll_cb(uv_poll_t* handle, int status, int events);
extern void handle_prepare_cb(uv_prepare_t* handle);
extern void handle_timer_cb(uv_timer_t* handle);

/* handle functions */
SV * handle_bless(pTHX_ uv_handle_t *h)
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

void handle_data_destroy(pTHX_ handle_data_t *data_ptr)
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
    if (NULL != data_ptr->poll_cb) {
        SvREFCNT_dec(data_ptr->poll_cb);
        data_ptr->poll_cb = NULL;
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
}

handle_data_t* handle_data_new(pTHX_ const uv_handle_type type)
{
    handle_data_t *data_ptr = (handle_data_t *)malloc(sizeof(handle_data_t));
    if (NULL == data_ptr) {
        croak("Cannot allocate space for handle data.");
    }

    /* set the stash */
    data_ptr->stash = gv_stashpv(handle_namespace(aTHX_ type), GV_ADD);
    if (NULL == data_ptr->stash) {
        free(data_ptr);
        croak("Invalid handle type supplied (%i)", type);
    }

    /* setup the user data */
    data_ptr->user_data = NULL;

    /* setup the callback slots */
    data_ptr->alloc_cb = NULL;
    data_ptr->check_cb = NULL;
    data_ptr->close_cb = NULL;
    data_ptr->idle_cb = NULL;
    data_ptr->poll_cb = NULL;
    data_ptr->prepare_cb = NULL;
    data_ptr->timer_cb = NULL;
    return data_ptr;
}

void handle_destroy(pTHX_ uv_handle_t *handle)
{
    if (NULL == handle) return;
    if (0 == uv_is_closing(handle) && 0 == uv_is_active(handle)) {
        uv_close(handle, handle_close_cb);
        handle_data_destroy(aTHX_ handle_data(handle));
        /*Safefree(handle);*/
    }
}

uv_handle_t* handle_new(pTHX_ const uv_handle_type type)
{
    uv_handle_t *handle;
    SV *self;
    handle_data_t *data_ptr = handle_data_new(aTHX_ type);
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

const char* handle_namespace(pTHX_ const uv_handle_type type)
{
    switch (type) {
        case UV_ASYNC: return "UV::Async";
        case UV_CHECK: return "UV::Check";
        case UV_FS_EVENT: return "UV::FSEvent";
        case UV_FS_POLL: return "UV::FSPoll";
        case UV_IDLE: return "UV::Idle";
        case UV_NAMED_PIPE: return "UV::NamedPipe";
        case UV_POLL: return "UV::Poll";
        case UV_PREPARE: return "UV::Prepare";
        case UV_PROCESS: return "UV::Process";
        case UV_STREAM: return "UV::Stream";
        case UV_TCP: return "UV::TCP";
        case UV_TIMER: return "UV::Timer";
        case UV_TTY: return "UV::TTY";
        case UV_UDP: return "UV::UDP";
        case UV_SIGNAL: return "UV::Signal";
        default:
            croak("Invalid handle type supplied");
    }
    return NULL;
}

void handle_on(pTHX_ uv_handle_t *handle, const char *name, SV *cb)
{
    SV *callback = NULL;
    handle_data_t *data_ptr = handle_data(handle);
    if (!data_ptr) return;

    callback = cb ? handle_get_cv_croak(cb) : NULL;

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
    else if (strEQ(name, "poll")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->poll_cb) {
            SvREFCNT_dec(data_ptr->poll_cb);
            data_ptr->poll_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->poll_cb = SvREFCNT_inc(callback);
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
void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf)
{
    handle_data_t *data_ptr = handle_data(handle);
    buf->base = malloc(suggested_size);
    buf->len = suggested_size;

    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->alloc_cb) return;
    dTHX;

    /* provide info to the caller: invocant, suggested_size */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 2);
    PUSHs(handle_bless(aTHX_ handle)); /* invocant */
    mPUSHi(suggested_size);

    PUTBACK;
    call_sv(data_ptr->alloc_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

void handle_check_cb(uv_check_t* handle)
{
    handle_data_t *data_ptr = handle_data(handle);

    /* call the close_cb if we have one */
    dTHX;
    if (NULL != data_ptr && NULL != data_ptr->check_cb) {
        /* provide info to the caller: invocant */
        dSP;
        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(handle_bless(aTHX_ (uv_handle_t *)handle)); /* invocant */

        PUTBACK;
        call_sv(data_ptr->check_cb, G_VOID);
        SPAGAIN;

        FREETMPS;
        LEAVE;
    }
}

void handle_close_cb(uv_handle_t* handle)
{
    handle_data_t *data_ptr = handle_data(handle);

    dTHX;
    /* call the close_cb if we have one */
    if (NULL != data_ptr && NULL != data_ptr->close_cb) {
        /* provide info to the caller: invocant */
        dSP;
        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(handle_bless(aTHX_ handle)); /* invocant */

        PUTBACK;
        call_sv(data_ptr->close_cb, G_VOID);
        SPAGAIN;

        FREETMPS;
        LEAVE;
    }
}

void handle_idle_cb(uv_idle_t* handle)
{
    handle_data_t *data_ptr = handle_data(handle);
    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->idle_cb) return;
    dTHX;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *) handle)); /* invocant */

    PUTBACK;
    call_sv(data_ptr->idle_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

void handle_poll_cb(uv_poll_t* handle, int status, int events)
{
    handle_data_t *data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->poll_cb) return;
    dTHX;

    /* provide info to the caller: invocant, status, events */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *)handle)); /* invocant */
    mPUSHi(status);
    mPUSHi(events);

    PUTBACK;
    call_sv(data_ptr->poll_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

void handle_prepare_cb(uv_prepare_t* handle)
{
    handle_data_t *data_ptr = handle_data(handle);
    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->prepare_cb) return;
    dTHX;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *) handle)); /* invocant */

    PUTBACK;
    call_sv(data_ptr->prepare_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

void handle_timer_cb(uv_timer_t* handle)
{
    handle_data_t *data_ptr = handle_data(handle);
    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->timer_cb) return;
    dTHX;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *) handle)); /* invocant */

    PUTBACK;
    call_sv(data_ptr->timer_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

#endif
