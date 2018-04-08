#if !defined (P5UV_LOOPS_HANDLES_H)
#define P5UV_LOOPS_HANDLES_H

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
    SV *user_data;
    int closed;
    /* callbacks available */
    AV *events;
    HV *callbacks;
} handle_data_t;

/* data to store with a LOOP */
typedef struct loop_data_s {
    SV *self;
    int is_default;
    int closed;
    /* callbacks available */
    AV *events;
    HV *callbacks;
} loop_data_t;

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

/* Handle function definitions */
extern void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf);
extern void handle_check_cb(uv_check_t* handle);
extern void handle_close_cb(uv_handle_t* handle);
extern void handle_close_destroy_cb(uv_handle_t* handle);
extern void handle_idle_cb(uv_idle_t* handle);
extern void handle_poll_cb(uv_poll_t* handle, int status, int events);
extern void handle_prepare_cb(uv_prepare_t* handle);
extern void handle_timer_cb(uv_timer_t* handle);

extern SV * handle_bless(pTHX_ uv_handle_t *h);
extern void handle_data_destroy(pTHX_ handle_data_t *data_ptr);
extern handle_data_t* handle_data_new(pTHX);
extern void handle_destroy(pTHX_ uv_handle_t *handle);
extern int handle_closed(pTHX_ const uv_handle_t *handle);
extern uv_handle_t* handle_new(pTHX_ SV *class, const uv_handle_type type);

/* Loop function definitions */
extern void loop_walk_cb(uv_handle_t* handle, void* arg);
extern void loop_walk_close_cb(uv_handle_t* handle, void* arg);

extern SV * loop_bless(pTHX_ uv_loop_t *loop);
extern loop_data_t* loop_data_new(pTHX);
extern void loop_data_destroy(pTHX_ loop_data_t *data_ptr);
extern int loop_closed(pTHX_ const uv_loop_t *loop);
extern uv_loop_t* loop_new(pTHX_ SV *class, int want_default);
extern int loop_is_default(pTHX_ const uv_loop_t *loop);


/* loop functions */
SV* loop_bless(pTHX_ uv_loop_t *loop)
{
    loop_data_t *data_ptr = loop_data(loop);
    if (!data_ptr || !data_ptr->self) {
        croak("Couldn't get the loop data");
    }
    return SvREFCNT_inc( (SV *)(data_ptr->self) );
    // return newSVsv(data_ptr->self);
}

void loop_data_destroy(pTHX_ loop_data_t *data_ptr)
{
    if (NULL == data_ptr) return;
    av_undef(data_ptr->events);
    hv_undef(data_ptr->callbacks);

    /* cleanup self */
    if (NULL != data_ptr->self) {
        SvREFCNT_dec((SV *)(data_ptr->self));
        data_ptr->self = NULL;
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
    data_ptr->events = newAV();
    data_ptr->callbacks = newHV();
    av_push(data_ptr->events, newSVpv("walk", 0));
    hv_store(data_ptr->callbacks, "on_walk", 7, newSV(0), 0);
    return data_ptr;
}

int loop_closed(pTHX_ const uv_loop_t *loop)
{
    loop_data_t *data_ptr;
    if (!loop || !loop->data) return 1;
    data_ptr = (loop_data_t *)loop->data;
    if (!data_ptr) return 1;
    return data_ptr->closed;
}

uv_loop_t * loop_new(pTHX_ SV *class, int want_default)
{
    int ret;
    loop_data_t *data_ptr;
    uv_loop_t *loop;
    if (want_default == 0) {
        Newx(loop, 1, uv_loop_t);
        if (NULL == loop) {
            croak("Unable to allocate space for a new loop");
        }
        ret = uv_loop_init(loop);
        if (0 != ret) {
            Safefree(loop);
            croak("Error initializing loop (%i): %s", ret, uv_strerror(ret));
        }
    }
    else {
        loop = uv_default_loop();
        if (!loop) {
            croak("Error getting a new default loop");
        }
    }
    data_ptr = loop_data_new(aTHX);
    data_ptr->self = sv_bless(
        newRV_noinc(newSViv(PTR2IV(loop))),
        gv_stashsv(class, GV_ADD)
    );
    if (want_default) data_ptr->is_default = 1;
    loop->data = (void *)data_ptr;
    return loop;
}

int loop_is_default(pTHX_ const uv_loop_t *loop)
{
    loop_data_t *data_ptr;
    if (!loop) return 0;
    data_ptr = (loop_data_t *)(loop->data);
    if (!data_ptr) return 0;
    return data_ptr->is_default;
}

void loop_walk_cb(uv_handle_t* handle, void* arg)
{
    SV *cb;

    dTHX;

    if (!handle || !arg) return;
    cb = (SV *)arg;
    if (!cb || !SvOK(cb)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ handle)); /* invocant */
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

void loop_walk_close_cb(uv_handle_t* handle, void* arg)
{
    dTHX;
    /* don't attempt to close an already closing handle */
    if (!handle || uv_is_closing(handle)) return;

    uv_close(handle, handle_close_destroy_cb);
}

/* handle functions */
SV * handle_bless(pTHX_ uv_handle_t *h)
{
    SV *rv;
    handle_data_t *data_ptr = (handle_data_t *)(h->data);
    if (!data_ptr || !data_ptr->self) {
        croak("Unable to find this Handle object");
    }
    return SvREFCNT_inc( (SV *)(data_ptr->self) );

    // return newSVsv(data_ptr->self);
}

void handle_data_destroy(pTHX_ handle_data_t *data_ptr)
{
    if (NULL == data_ptr) return;

    /* cleanup self, loop_sv, user_data, and stash */
    if (NULL != data_ptr->self) {
        SvREFCNT_dec(data_ptr->self);
        data_ptr->self = NULL;
    }
    av_undef(data_ptr->events);
    hv_undef(data_ptr->callbacks);
    Safefree(data_ptr);
}

int handle_closed(pTHX_ const uv_handle_t *handle)
{
    handle_data_t *data_ptr;
    if (!handle) return 1;
    data_ptr = (handle_data_t *)handle->data;
    if (!data_ptr) return 1;
    return data_ptr->closed;
}

handle_data_t* handle_data_new(pTHX)
{
    handle_data_t *data_ptr = (handle_data_t *)malloc(sizeof(handle_data_t));
    if (NULL == data_ptr) {
        croak("Cannot allocate space for handle data.");
    }

    data_ptr->self = NULL;
    /* setup the user data */
    data_ptr->closed = 0;
    data_ptr->user_data = NULL;
    data_ptr->events = newAV();
    data_ptr->callbacks = newHV();

    av_push(data_ptr->events, newSVpv("alloc", 0));
    av_push(data_ptr->events, newSVpv("close", 0));
    hv_store(data_ptr->callbacks, "on_alloc", 8, newSV(0), 0);
    hv_store(data_ptr->callbacks, "on_close", 8, newSV(0), 0);

    /* setup the callback slots */
    return data_ptr;
}

void handle_destroy(pTHX_ uv_handle_t *handle)
{
    handle_data_t *data_ptr;
    if (NULL == handle) return;
    /* attempt to remove the two-way circular reference */
    if (handle->data) {
        data_ptr = (handle_data_t *)(handle->data);
        if (data_ptr) {
            handle_data_destroy(aTHX_ data_ptr);
            handle->data = NULL;
        }
    }
    uv_unref(handle);
    Safefree(handle);
}

uv_handle_t* handle_new(pTHX_ SV *class, const uv_handle_type type)
{
    uv_handle_t *handle;
    handle_data_t *data_ptr;
    size_t size = uv_handle_size(type);
    handle = (uv_handle_t *)malloc(size);
    if (NULL == handle) {
        croak("Cannot allocate space for a new uv_handle_t");
    }

    /* add some data to our new handle */
    data_ptr = handle_data_new(aTHX);
    data_ptr->self = sv_bless(
        newRV_noinc(newSViv(PTR2IV(handle))),
        gv_stashsv(class, GV_ADD)
    );
    handle->data = (void *)data_ptr;
    return handle;
}

/* HANDLE callbacks */
void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf)
{
    dTHX;
    SV **callback;
    handle_data_t *data_ptr;
    buf->base = malloc(suggested_size);
    buf->len = suggested_size;


    if (!handle || !handle->data) return;
    data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_alloc", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant, suggested_size */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 2);
    PUSHs(handle_bless(aTHX_ handle)); /* invocant */
    mPUSHi(suggested_size);
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

void handle_check_cb(uv_check_t* handle)
{
    SV **callback;
    handle_data_t *data_ptr;

    dTHX;

    if (!handle || !handle->data) return;
    data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_check", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *)handle)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

void handle_close_cb(uv_handle_t* handle)
{
    SV **callback;
    handle_data_t *data_ptr;

    dTHX;

    if (!handle || !handle->data) return;
    data_ptr = handle_data(handle);
    data_ptr->closed = 1;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_close", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ handle)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

void handle_close_destroy_cb(uv_handle_t* handle)
{
    SV **callback;
    handle_data_t *data_ptr;
    if (!handle) return;

    dTHX;

    data_ptr = handle_data(handle);
    if (!data_ptr) {
        handle_destroy(aTHX_ handle);
        return;
    }
    data_ptr->closed = 1;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_close", FALSE);
    if (!callback || !SvOK(*callback)) {
        handle_destroy(aTHX_ handle);
        return;
    }

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ handle)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
    handle_destroy(aTHX_ handle);
}

void handle_idle_cb(uv_idle_t* handle)
{
    SV **callback;
    handle_data_t *data_ptr;

    dTHX;

    if (!handle || !handle->data) return;
    data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_idle", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *)handle)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

void handle_poll_cb(uv_poll_t* handle, int status, int events)
{
    SV **callback;
    handle_data_t *data_ptr;

    dTHX;

    if (!handle || !handle->data) return;
    data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_poll", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *)handle)); /* invocant */
    mPUSHi(status);
    mPUSHi(events);
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

void handle_prepare_cb(uv_prepare_t* handle)
{
    SV **callback;
    handle_data_t *data_ptr;

    dTHX;

    if (!handle || !handle->data) return;
    data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_prepare", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *)handle)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

void handle_timer_cb(uv_timer_t* handle)
{
    SV **callback;
    handle_data_t *data_ptr;

    dTHX;

    if (!handle || !handle->data) return;
    data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs(data_ptr->callbacks, "on_timer", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(handle_bless(aTHX_ (uv_handle_t *)handle)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}


#endif
