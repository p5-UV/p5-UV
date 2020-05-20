#define PERL_NO_GET_CONTEXT 1

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newCONSTSUB
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

#include "perl-backcompat.h"
#include "uv-backcompat.h"

#if defined(__MINGW32__) || defined(WIN32)
#include <io.h> /* we need _get_osfhandle() on windows */
#define _MAKE_SOCK(s, f) s = _get_osfhandle(f)
#else
#define _MAKE_SOCK(s,f) s = f
#endif

static void p5uv_destroy_handle(pTHX_ uv_handle_t * handle)
{
    SV *self;
    if (!handle) return;
    /* attempt to remove the two-way circular reference */
    if (handle->data) {
        self = (SV *)(handle->data);
        if (self && SvROK(self)) {
            xs_object_magic_detach_struct_rv(aTHX_ self, handle);
            self = NULL;
            SvREFCNT_dec((SV *)(handle->data));
        }
        handle->data = NULL;
    }
    uv_unref(handle);
    Safefree(handle);
}

/* HANDLE callbacks */
static void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf)
{
    SV *self;
    SV **callback;

    dTHX;

    buf->base = malloc(suggested_size);
    buf->len = suggested_size;
    if (!handle || !handle->data) return;

    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) return;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_alloc", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant, suggested_size */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 2);
    PUSHs(sv_2mortal(SvREFCNT_inc(self))); /* invocant */
    mPUSHi(suggested_size);
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void handle_check_cb(uv_check_t* handle)
{
    SV *self;
    SV **callback;

    dTHX;

    if (!handle || !handle->data) return;
    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) return;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_check", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(SvREFCNT_inc(self)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void handle_close_cb(uv_handle_t* handle)
{
    SV *self;
    SV **callback;

    dTHX;

    if (!handle || !handle->data) return;

    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) return;
    hv_stores((HV *)SvRV(self), "_closed", newSViv(1));

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_close", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(SvREFCNT_inc(self)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void handle_close_destroy_cb(uv_handle_t* handle)
{
    SV *self;
    SV **callback;

    dTHX;

    if (!handle) return;

    if (!handle->data) {
        p5uv_destroy_handle(aTHX_ handle);
        return;
    }

    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) {
        p5uv_destroy_handle(aTHX_ handle);
        return;
    }
    hv_stores((HV *)SvRV(self), "_closed", newSViv(1));

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_close", FALSE);
    if (!callback || !SvOK(*callback)) {
        p5uv_destroy_handle(aTHX_ handle);
        return;
    }

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(SvREFCNT_inc(self)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
    p5uv_destroy_handle(aTHX_ handle);
}

static void handle_idle_cb(uv_idle_t* handle)
{
    SV *self;
    SV **callback;

    dTHX;

    if (!handle || !handle->data) return;
    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) return;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_idle", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(SvREFCNT_inc(self)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void handle_poll_cb(uv_poll_t* handle, int status, int events)
{
    SV *self;
    SV **callback;

    dTHX;

    if (!handle || !handle->data) return;
    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) return;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_poll", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant, status, events */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(SvREFCNT_inc(self)); /* invocant */
    mPUSHi(status);
    mPUSHi(events);

    PUTBACK;
    call_sv(*callback, G_DISCARD|G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

static void handle_prepare_cb(uv_prepare_t* handle)
{
    SV *self;
    SV **callback;

    dTHX;

    if (!handle || !handle->data) return;
    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) return;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_prepare", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(SvREFCNT_inc(self)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void handle_timer_cb(uv_timer_t* handle)
{
    SV *self;
    SV **callback;

    dTHX;

    if (!handle || !handle->data) return;
    self = (SV *)(handle->data);
    if (!self || !SvROK(self)) return;

    /* nothing else to do if we don't have a callback to call */
    callback = hv_fetchs((HV*)SvRV(self), "_on_timer", FALSE);
    if (!callback || !SvOK(*callback)) return;

    /* provide info to the caller: invocant */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(SvREFCNT_inc(self)); /* invocant */
    PUTBACK;

    call_sv(*callback, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void loop_walk_cb(uv_handle_t* handle, void* arg)
{
    SV *self;
    SV *cb;

    dTHX;

    if (!handle || !arg) return;
    cb = (SV *)arg;
    if (!cb || !SvOK(cb)) return;

    self = (SV *)(handle->data);

    /* provide info to the caller: invocant, suggested_size */
    dSP;
    ENTER;
    SAVETMPS;

    if (self && SvROK(self)) {
        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(SvREFCNT_inc(self)); /* invocant */
        PUTBACK;
    }

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void loop_walk_close_cb(uv_handle_t* handle, void* arg)
{
    SV *self;
    dTHX;
    /* don't attempt to close an already closing handle */
    if (!handle || uv_is_closing(handle)) return;
    if (!handle->data) return;
    self = (SV *)(handle->data);
    if (!self) return;

    uv_close(handle, handle_close_destroy_cb);
}

/************
 * UV::Loop *
 ************/

typedef struct UV__Loop {
    uv_loop_t _loop;
    uv_loop_t *loop; /* may point to _loop */
    SV *on_walk;     /* TODO as yet unused and probably not correct */
} *UV__Loop;

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

MODULE = UV             PACKAGE = UV::Loop

SV *
_new(char *class, int want_default)
    INIT:
        UV__Loop self;
        int ret;
    CODE:
        Newx(self, 1, struct UV__Loop);
        self->on_walk = NULL;

        if(want_default) {
            self->loop = uv_default_loop();
        }
        else {
            ret = uv_loop_init(&self->_loop);
            if(ret != 0) {
                Safefree(self);
                croak("Error initialising loop (%d): %s", ret, uv_strerror(ret));
            }
            self->loop = &self->_loop;
        }

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Loop", self);
    OUTPUT:
        RETVAL

SV *
_on_walk(UV::Loop self, SV *cb = NULL)
    CODE:
        if(cb && SvOK(cb)) {
            if(self->on_walk)
                SvREFCNT_dec(self->on_walk);

            self->on_walk = newSVsv(cb);
        }

        RETVAL = newSVsv(self->on_walk);
    OUTPUT:
        RETVAL

int
alive(UV::Loop self)
    CODE:
        RETVAL = uv_loop_alive(self->loop);
    OUTPUT:
        RETVAL

int
backend_fd(UV::Loop self)
    CODE:
        RETVAL = uv_backend_fd(self->loop);
    OUTPUT:
        RETVAL

int
backend_timeout(UV::Loop self)
    CODE:
        RETVAL = uv_backend_timeout(self->loop);
    OUTPUT:
        RETVAL

void
DESTROY(UV::Loop self)
    CODE:
        /* Don't allow closing the default loop */
        if(self->loop != uv_default_loop())
            uv_loop_close(self->loop);

int
configure(UV::Loop self, int option, int value)
    CODE:
        RETVAL = uv_loop_configure(self->loop, option, value);
    OUTPUT:
        RETVAL

int
is_default(UV::Loop self)
    CODE:
        RETVAL = (self->loop == uv_default_loop());
    OUTPUT:
        RETVAL

UV
now(UV::Loop self)
    CODE:
        RETVAL = uv_now(self->loop);
    OUTPUT:
        RETVAL

int
run(UV::Loop self, int mode = UV_RUN_DEFAULT)
    CODE:
        RETVAL = uv_run(self->loop, mode);
    OUTPUT:
        RETVAL

void
stop(UV::Loop self)
    CODE:
        uv_stop(self->loop);

void
update_time(UV::Loop self)
    CODE:
        uv_update_time(self->loop);
