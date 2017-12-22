#if !defined (P5UV_BASE_H)
#define P5UV_BASE_H

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"
#include <uv.h>

#define handle_data(h)      ((handle_data_t *)((uv_handle_t *)(h))->data)
#define loop_data(l)        ((loop_data_t *)((uv_loop_t *)(l))->data)

/* data to store with a HANDLE */
typedef struct handle_data_s {
    SV *self;
    HV *stash;
    SV *user_data;
    int closed;
    int closing;

    /* callbacks available */
    SV *alloc_cb;
    SV *check_cb;
    SV *close_cb;
    SV *idle_cb;
    SV *poll_cb;
    SV *prepare_cb;
    SV *timer_cb;
} handle_data_t;

/* data to store with a LOOP */
typedef struct loop_data_s {
    SV *self;
    int is_default;
    int closed;

    /* Handles and Requests */
    AV *handles;
    AV *requests;
    AV *handles_to_close;
    AV *requests_to_close;

    /* callbacks available */
    SV *walk_cb;
} loop_data_t;

/* helper functions and callbacks */
static SV * get_cv_croak(SV *cb_sv);
extern void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf);
extern void handle_check_cb(uv_check_t* handle);
extern void handle_close_cb(uv_handle_t* handle);
extern void handle_idle_cb(uv_idle_t* handle);
extern void handle_poll_cb(uv_poll_t* handle, int status, int events);
extern void handle_prepare_cb(uv_prepare_t* handle);
extern void handle_timer_cb(uv_timer_t* handle);
extern void loop_walk_cb(uv_handle_t* handle, void* arg);
extern void loop_walk_close_cb(uv_handle_t* handle, void* arg);


/* Handle function definitions */
extern SV *             handle_bless(pTHX_ uv_handle_t *h);
extern void             handle_close(pTHX_ uv_handle_t* handle);
extern void             handle_data_destroy(pTHX_ handle_data_t *data_ptr);
extern handle_data_t*   handle_data_new(pTHX_ const uv_handle_type type, const char* namespace);
extern uv_handle_t*     handle_new(pTHX_ const uv_handle_type type, const char* namespace);
extern void             handle_on(pTHX_ uv_handle_t *handle, const char *name, SV *cb);
static void             handle_set_closed(pTHX_ uv_handle_t* handle);

/* Loop function definitions */
extern int          loop_alive(pTHX_ const uv_loop_t *loop);
extern void         loop_attach_handle(pTHX_ uv_loop_t *loop, uv_handle_t *handle);
extern void         loop_attach_request(pTHX_ uv_loop_t *loop, uv_req_t *handle);
extern SV*          loop_bless(pTHX_ uv_loop_t *loop);
extern int          loop_close(pTHX_ uv_loop_t *loop);
extern loop_data_t* loop_data_new(pTHX);
extern void         loop_data_destroy(pTHX_ loop_data_t *data_ptr);
extern uv_loop_t*   loop_default(pTHX);
extern void         loop_destroy(pTHX_ uv_loop_t *loop);
extern void         loop_detach_handle(pTHX_ uv_loop_t *loop, uv_handle_t *handle);
static SSize_t      loop_has_handle(pTHX_ uv_loop_t *loop, uv_handle_t *handle);
extern uv_loop_t*   loop_new(pTHX);
extern void         loop_on(pTHX_ uv_loop_t *loop, const char *name, SV *cb);

/* helper functions and callbacks */
SV * get_cv_croak(SV *cb_sv)
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

    handle_set_closed(aTHX_ handle);

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

void loop_walk_cb(uv_handle_t* handle, void* arg)
{
    SV *callback;
    if (NULL == arg || (SV *)arg == &PL_sv_undef) return;
    dTHX;
    callback = arg ? get_cv_croak((SV *)arg) : NULL;
    if (NULL == callback) return;

    /* provide info to the caller: invocant, suggested_size */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ handle)); /* invocant */

    PUTBACK;
    call_sv(callback, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

void loop_walk_close_cb(uv_handle_t* handle, void* arg)
{
    if (!uv_is_closing(handle)) {
        uv_close(handle, NULL);
    }
}



/* handle functions */
SV * handle_bless(pTHX_ uv_handle_t *h)
{
    SV *rv;
    handle_data_t *data_ptr = handle_data(h);

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

void handle_close(pTHX_ uv_handle_t *handle)
{
    handle_data_t *data_ptr = handle_data(handle);
    if (!data_ptr->closing) {
        data_ptr->closing = 1;
        uv_close(handle, handle_close_cb);
    }
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

handle_data_t* handle_data_new(pTHX_ const uv_handle_type type, const char* ns)
{
    handle_data_t *data_ptr = (handle_data_t *)malloc(sizeof(handle_data_t));
    if (NULL == data_ptr) {
        croak("Cannot allocate space for handle data.");
    }

    /* set the stash */
    data_ptr->stash = gv_stashpv(ns, GV_ADD);
    if (NULL == data_ptr->stash) {
        free(data_ptr);
        croak("Invalid handle type supplied (%i)", type);
    }

    data_ptr->closed = 0;
    data_ptr->closing = 0;
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

uv_handle_t* handle_new(pTHX_ const uv_handle_type type, const char* ns)
{
    uv_handle_t *handle;
    SV *self;
    handle_data_t *data_ptr = handle_data_new(aTHX_ type, ns);
    size_t size = uv_handle_size(type);

    self = NEWSV(0, size);
    SvPOK_only(self);
    SvCUR_set(self, size);
    handle = (uv_handle_t *) SvPVX(self);
    if (NULL == handle) {
        handle_data_destroy(aTHX_ data_ptr);
        data_ptr = NULL;
        Safefree(self);
        croak("Cannot allocate space for a new uv_handle_t");
    }

    /* add some data to our new handle */
    data_ptr->self = self;
    handle->data = (void *)data_ptr;
    return handle;
}

void handle_on(pTHX_ uv_handle_t *handle, const char *name, SV *cb)
{
    SV *callback = NULL;
    handle_data_t *data_ptr = handle_data(handle);
    if (!data_ptr) return;

    callback = cb ? get_cv_croak(cb) : NULL;

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

void handle_set_closed(pTHX_ uv_handle_t* handle)
{
    handle_data_t *data_ptr = handle_data(handle);
    data_ptr->closed = 1;
    loop_detach_handle(aTHX_ handle->loop, handle);
}



/* loop functions */
int loop_alive(pTHX_ const uv_loop_t *loop)
{
    loop_data_t *data_ptr = loop_data(loop);
    if (!data_ptr || data_ptr->closed) {
        return 0;
    }
    return uv_loop_alive(loop);
}

void loop_attach_handle(pTHX_ uv_loop_t *loop, uv_handle_t *handle)
{
    /* check for its existence first */
    SSize_t i = loop_has_handle(aTHX_ loop, handle);
    if (i >= 0) return;

    av_push(loop_data(loop)->handles, handle_bless(aTHX_ handle));
}

void loop_attach_request(pTHX_ uv_loop_t *loop, uv_req_t *req)
{
    loop_data_t *data_ptr = loop_data(loop);
    if (!data_ptr) croak("Invalid loop provided.");
    croak("TODO: not yet implemented");
}

SV* loop_bless(pTHX_ uv_loop_t *loop)
{
    loop_data_t *data_ptr = loop_data(loop);
    if (!data_ptr || !data_ptr->self) {
        croak("Couldn't get the loop data");
    }

    return newSVsv(data_ptr->self);
}

int loop_close(pTHX_ uv_loop_t *loop)
{
    loop_data_t *data_ptr = loop_data(loop);
    int code;
    if (!data_ptr) {
        croak("No data pointer available");
    }
    if (data_ptr->closed) return 0;

    uv_walk(loop, loop_walk_close_cb, NULL);
    uv_run(loop, UV_RUN_DEFAULT);

    code = uv_loop_close(loop);
    if (code == 0) {
        data_ptr->closed = 1;
    }
    return code;
}

void loop_data_destroy(pTHX_ loop_data_t *data_ptr)
{
    if (NULL == data_ptr) return;

    /* cleanup self */
    if (NULL != data_ptr->self) {
        data_ptr->self = NULL;
    }
    /* cleanup arrays of handles and requests */
    av_clear(data_ptr->handles);
    av_clear(data_ptr->requests);
    av_clear(data_ptr->handles_to_close);
    av_clear(data_ptr->requests_to_close);
    /* cleanup callbacks */
    if (NULL != data_ptr->walk_cb) {
        SvREFCNT_dec(data_ptr->walk_cb);
        data_ptr->walk_cb = NULL;
    }
    Safefree(data_ptr);
}

loop_data_t* loop_data_new(pTHX)
{
    loop_data_t *data_ptr = (loop_data_t *)malloc(sizeof(loop_data_t));
    if (NULL == data_ptr) {
        croak("Cannot allocate space for loop data.");
    }
    data_ptr->self = NULL;
    data_ptr->is_default = 0;
    data_ptr->closed = 0;

    /* Arrays to help control handles and requests closure */
    data_ptr->handles = newAV();
    data_ptr->requests = newAV();
    data_ptr->handles_to_close = newAV();
    data_ptr->requests_to_close = newAV();

    /* setup the callback slots */
    data_ptr->walk_cb = NULL;
    return data_ptr;
}

uv_loop_t * loop_default(pTHX)
{
    loop_data_t *data_ptr;
    uv_loop_t *loop = uv_default_loop();
    if (!loop) {
        croak("Error getting a new default loop");
    }
    data_ptr = loop_data(loop);
    if (!data_ptr) data_ptr = loop_data_new(aTHX);

    if (!data_ptr->self) {
        data_ptr->self = sv_bless(
            newRV_noinc(newSViv(PTR2IV(loop))),
            gv_stashpv("UV::Loop", GV_ADD)
        );
        loop->data = (void *)data_ptr;
    }
    data_ptr->is_default = 1;
    return loop;
}

void loop_destroy(pTHX_ uv_loop_t *loop)
{
    loop_data_t *data_ptr;
    int perform_free = 1;
    if (!loop) return;
    data_ptr = (loop_data_t *)loop->data;
    if (!data_ptr || !data_ptr->self) return;
    if (data_ptr->is_default && !PL_dirty) return;
    if (data_ptr->is_default) perform_free = 0;
    if (!data_ptr->closed) {
        uv_walk(loop, loop_walk_close_cb, NULL);
        uv_run(loop, UV_RUN_DEFAULT);
        loop_close(loop);
        loop->data = NULL;
        if (data_ptr) loop_data_destroy(aTHX_ data_ptr);
        if (perform_free) Safefree(loop);
    }
}

void loop_detach_handle(pTHX_ uv_loop_t *loop, uv_handle_t *handle)
{
    /* check for its existence first */
    SSize_t i = loop_has_handle(aTHX_ loop, handle);
    if (i >= 0) {
        av_delete(loop_data(loop)->handles, i, 0);
    }
}

SSize_t loop_has_handle(pTHX_ uv_loop_t *loop, uv_handle_t *handle)
{
    SSize_t i, len;
    SV *blessed_handle, *tmp;
    loop_data_t *data_ptr = loop_data(loop);
    if (!data_ptr) croak("Invalid loop provided.");
    if (!handle) croak("Invalid handle provided.");
    blessed_handle = handle_bless(aTHX_ handle);
    if (!blessed_handle) croak("Invalid handle provided.");

    /* must add 1 to av_len result */
    len = av_len(data_ptr->handles) + 1;
    for (i = 0; i < len; i++) {
        SV **item = av_fetch(data_ptr->handles, i, 0);
        if (item && (*item) == blessed_handle) return i;
    }
    return -1;
}

uv_loop_t * loop_new(pTHX)
{
    int ret;
    loop_data_t *data_ptr;
    uv_loop_t *loop;
    Newx(loop, 1, uv_loop_t);
    if (NULL == loop) {
        croak("Unable to allocate space for a new loop");
    }
    ret = uv_loop_init(loop);
    if (0 != ret) {
        Safefree(loop);
        croak("Error initializing loop (%i): %s", ret, uv_strerror(ret));
    }
    data_ptr = loop_data_new(aTHX);
    data_ptr->self = sv_bless(
        newRV_noinc(newSViv(PTR2IV(loop))),
        gv_stashpv("UV::Loop", GV_ADD)
    );
    loop->data = (void *)data_ptr;
    data_ptr->is_default = 0;

    loop->data = (void *)data_ptr;
    return loop;
}

void loop_on(pTHX_ uv_loop_t *loop, const char *name, SV *cb)
{
    loop_data_t *data_ptr = loop_data(loop);
    SV *callback = NULL;
    if (!data_ptr) return;

    if (NULL != cb && (SV *)cb != &PL_sv_undef) {
        callback = cb ? get_cv_croak(cb) : NULL;
    }

    /* find out which callback to set */
    if (strEQ(name, "walk")) {
        /* clear the callback's current value first */
        if (NULL != data_ptr->walk_cb) {
            SvREFCNT_dec(data_ptr->walk_cb);
            data_ptr->walk_cb = NULL;
        }
        /* set the CB */
        if (NULL != callback) {
            data_ptr->walk_cb = SvREFCNT_inc(callback);
        }
    }
}

#endif
