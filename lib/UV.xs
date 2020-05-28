#define PERL_NO_GET_CONTEXT 1

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newCONSTSUB
#include "ppport.h"

#include <assert.h>
#include <stdlib.h>

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
#  define _MAKE_SOCK(f) (_get_osfhandle(f))
#else
#  define _MAKE_SOCK(f) (f)
#endif

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

#define do_callback_accessor(var, cb) MY_do_callback_accessor(aTHX_ var, cb)
static SV *MY_do_callback_accessor(pTHX_ SV **var, SV *cb)
{
    if(cb && SvOK(cb)) {
        if(*var)
            SvREFCNT_dec(*var);

        *var = newSVsv(cb);
    }

    if(*var && SvOK(*var))
        return SvREFCNT_inc(*var);
    else
        return &PL_sv_undef;
}

/**************
 * UV::Handle *
 **************/

struct UV__Handle_base {
    SV *selfrv; /* The underlying blessed RV itself */
#ifdef MULTIPLICITY
    tTHX perl;
#endif
    SV *data;   /* The arbitrary ->data value */
    SV *on_close;
};
typedef struct UV__Handle {
    struct UV__Handle_base base;
    uv_handle_t  handle;
} *UV__Handle;

#ifdef MULTIPLICITY
#  define storeTHX(var)  (var) = aTHX
#else
#  define storeTHX(var)  dNOOP
#endif

#define INIT_UV_HANDLE_BASE(h)  { \
  storeTHX((h).base.perl);        \
  (h).base.data     = NULL;       \
  (h).base.on_close = NULL;       \
}

static void destroy_handle(UV__Handle self);
static void destroy_handle_base(pTHX_ UV__Handle self)
{
    if(self->base.data)
        SvREFCNT_dec(self->base.data);
    if(self->base.on_close)
        SvREFCNT_dec(self->base.on_close);

    /* No need to destroy self->base.selfrv because Perl is already destroying
     * it, being the reason we are invoked in the first place
     */

    Safefree(self);
}

static void on_close_cb(uv_handle_t *handle)
{
    UV__Handle  self;
    SV         *cb;

    if(!handle || !handle->data) return;

    self = handle->data;
    if(!(cb = self->base.on_close) || !SvOK(cb)) return;

    dTHXa(self->base.perl);
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    mPUSHs(newRV_inc(self->base.selfrv));
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

static void on_close_then_destroy(uv_handle_t *handle)
{
    on_close_cb(handle);
    destroy_handle(handle->data);
}

/*************
 * UV::Check *
 *************/

/* See also http://docs.libuv.org/en/v1.x/check.html */

typedef struct UV__Check {
    struct UV__Handle_base base;
    uv_check_t  check;
    SV         *on_check;
} *UV__Check;

static void destroy_check(pTHX_ UV__Check self)
{
    if(self->on_check)
        SvREFCNT_dec(self->on_check);
}

static void on_check_cb(uv_check_t *check)
{
    UV__Check  self;
    SV        *cb;

    if(!check || !check->data) return;

    self = check->data;
    if(!(cb = self->on_check) || !SvOK(cb)) return;

    dTHXa(self->base.perl);
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    mPUSHs(newRV_inc(self->base.selfrv));
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

/************
 * UV::Idle *
 ************/

/* See also http://docs.libuv.org/en/v1.x/idle.html */

typedef struct UV__Idle {
    struct UV__Handle_base base;
    uv_idle_t  idle;
    SV        *on_idle;
} *UV__Idle;

static void destroy_idle(pTHX_ UV__Idle self)
{
    if(self->on_idle)
        SvREFCNT_dec(self->on_idle);
}

static void on_idle_cb(uv_idle_t *idle)
{
    UV__Idle self;
    SV       *cb;

    if(!idle || !idle->data) return;

    self = idle->data;
    if(!(cb = self->on_idle) || !SvOK(cb)) return;

    dTHXa(self->base.perl);
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    mPUSHs(newRV_inc(self->base.selfrv));
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

/************
 * UV::Poll *
 ************/

/* See also http://docs.libuv.org/en/v1.x/poll.html */

typedef struct UV__Poll {
    struct UV__Handle_base base;
    uv_poll_t  poll;
    SV        *on_poll;
} *UV__Poll;

static void destroy_poll(pTHX_ UV__Poll self)
{
    if(self->on_poll)
        SvREFCNT_dec(self->on_poll);
}

static void on_poll_cb(uv_poll_t *poll, int status, int events)
{
    UV__Poll self;
    SV       *cb;

    if(!poll || !poll->data) return;

    self = poll->data;
    if(!(cb = self->on_poll) || !SvOK(cb)) return;

    dTHXa(self->base.perl);
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    mPUSHs(newRV_inc(self->base.selfrv));
    mPUSHi(status);
    mPUSHi(events);
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

/***************
 * UV::Prepare *
 ***************/

/* See also http://docs.libuv.org/en/v1.x/prepare.html */

typedef struct UV__Prepare {
    struct UV__Handle_base base;
    uv_prepare_t  prepare;
    SV           *on_prepare;
} *UV__Prepare;

static void destroy_prepare(pTHX_ UV__Prepare self)
{
    if(self->on_prepare)
        SvREFCNT_dec(self->on_prepare);
}

static void on_prepare_cb(uv_prepare_t *prepare)
{
    UV__Prepare  self;
    SV          *cb;

    if(!prepare || !prepare->data) return;

    self = prepare->data;
    if(!(cb = self->on_prepare) || !SvOK(cb)) return;

    dTHXa(self->base.perl);
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    mPUSHs(newRV_inc(self->base.selfrv));
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

/**************
 * UV::Signal *
 **************/

/* See also http://docs.libuv.org/en/v1.x/signal.html */

typedef struct UV__Signal {
    struct UV__Handle_base base;
    uv_signal_t  signal;
    int          signum;
    SV          *on_signal;
} *UV__Signal;

static void destroy_signal(pTHX_ UV__Signal self)
{
    if(self->on_signal)
        SvREFCNT_dec(self->on_signal);
}

static void on_signal_cb(uv_signal_t *signal, int signum)
{
    UV__Signal self;
    SV         *cb;

    if(!signal || !signal->data) return;

    self = signal->data;
    if(!(cb = self->on_signal) || !SvOK(cb)) return;

    dTHXa(self->base.perl);
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 2);
    mPUSHs(newRV_inc(self->base.selfrv));
    mPUSHi(signum);
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

/*************
 * UV::Timer *
 *************/

/* See also http://docs.libuv.org/en/v1.x/timer.html */

typedef struct UV__Timer {
    struct UV__Handle_base base;
    uv_timer_t  timer;
    SV         *on_timer;
} *UV__Timer;

static void destroy_timer(pTHX_ UV__Timer self)
{
    if(self->on_timer)
        SvREFCNT_dec(self->on_timer);
}

static void on_timer_cb(uv_timer_t *timer)
{
    UV__Timer  self;
    SV        *cb;

    if(!timer || !timer->data) return;

    self = timer->data;
    if(!(cb = self->on_timer) || !SvOK(cb)) return;

    dTHXa(self->base.perl);
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    mPUSHs(newRV_inc(self->base.selfrv));
    PUTBACK;

    call_sv(cb, G_DISCARD|G_VOID);

    FREETMPS;
    LEAVE;
}

/* Handle destructor has to be able to see the type-specific destroy_
 * functions above, so must be last
 */

static void destroy_handle(UV__Handle self)
{
    dTHXa(self->base.perl);

    uv_handle_t *handle = &self->handle;
    switch(handle->type) {
        case UV_CHECK:   destroy_check  (aTHX_ (UV__Check)  self); break;
        case UV_IDLE:    destroy_idle   (aTHX_ (UV__Idle)   self); break;
        case UV_POLL:    destroy_poll   (aTHX_ (UV__Poll)   self); break;
        case UV_PREPARE: destroy_prepare(aTHX_ (UV__Prepare)self); break;
        case UV_SIGNAL:  destroy_signal (aTHX_ (UV__Signal) self); break;
        case UV_TIMER:   destroy_timer  (aTHX_ (UV__Timer)  self); break;
    }

    destroy_handle_base(aTHX_ self);
}

/************
 * UV::Loop *
 ************/

typedef struct UV__Loop {
    uv_loop_t _loop;
    uv_loop_t *loop; /* may point to _loop */
    SV *on_walk;     /* TODO as yet unused and probably not correct */
} *UV__Loop;

static void on_loop_walk(uv_handle_t* handle, void* arg)
{
    fprintf(stderr, "TODO: on_loop_walk\n");
}

MODULE = UV             PACKAGE = UV            PREFIX = uv_

BOOT:
{
    HV *stash;
    AV *export;
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

UV uv_hrtime()
    CODE:
        RETVAL = uv_hrtime();
    OUTPUT:
        RETVAL

const char* uv_strerror(int err)

unsigned int uv_version()

const char* uv_version_string()

MODULE = UV             PACKAGE = UV::Handle

void
DESTROY(UV::Handle self)
    CODE:
        /* TODO:
            $self->stop() if ($self->can('stop') && !$self->closing() && !$self->closed());
         */
        if(!uv_is_closing(&self->handle))
            uv_close(&self->handle, on_close_then_destroy);
        else
            destroy_handle(self);

bool
closed(UV::Handle self)
    CODE:
        RETVAL = 0;
    OUTPUT:
        RETVAL

bool
closing(UV::Handle self)
    CODE:
        RETVAL = uv_is_closing(&self->handle);
    OUTPUT:
        RETVAL

int
active(UV::Handle self)
    CODE:
        RETVAL = uv_is_active(&self->handle);
    OUTPUT:
        RETVAL

SV *
loop(UV::Handle self)
    INIT:
        UV__Loop loop;
    CODE:
        Newx(loop, 1, struct UV__Loop);
        loop->loop = self->handle.loop;
        loop->on_walk = NULL; /* this is a mess */

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Loop", loop);
    OUTPUT:
        RETVAL

SV *
data(UV::Handle self, SV *data = NULL)
    CODE:
        if(items > 1) {
            if(self->base.data)
                SvREFCNT_dec(self->base.data);
            self->base.data = newSVsv(data);
        }
        RETVAL = self->base.data ? newSVsv(self->base.data) : &PL_sv_undef;
    OUTPUT:
        RETVAL

void
_close(UV::Handle self)
    CODE:
        uv_close(&self->handle, on_close_cb);

SV *
_on_close(UV::Handle self, SV *cb = NULL)
    CODE:
        RETVAL = do_callback_accessor(&self->base.on_close, cb);
    OUTPUT:
        RETVAL

MODULE = UV             PACKAGE = UV::Check

SV *
_new(char *class, UV::Loop loop)
    INIT:
        UV__Check self;
        int ret;
    CODE:
        Newx(self, 1, struct UV__Check);
        ret = uv_check_init(loop->loop, &self->check);
        if (ret != 0) {
            Safefree(self);
            croak("Couldn't initialize check handle (%d): %s", ret, uv_strerror(ret));
        }
        self->check.data = self;

        INIT_UV_HANDLE_BASE(*self);
        self->on_check = NULL;

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Check", self);
        self->base.selfrv = SvRV(RETVAL); /* no inc */
    OUTPUT:
        RETVAL

SV *
_on_check(UV::Check self, SV *cb = NULL)
    CODE:
        RETVAL = do_callback_accessor(&self->on_check, cb);
    OUTPUT:
        RETVAL

int
_start(UV::Check self)
    CODE:
        RETVAL = uv_check_start(&self->check, on_check_cb);
    OUTPUT:
        RETVAL

int
stop(UV::Check self)
    CODE:
        RETVAL = uv_check_stop(&self->check);
    OUTPUT:
        RETVAL

MODULE = UV             PACKAGE = UV::Idle

SV *
_new(char *class, UV::Loop loop)
    INIT:
        UV__Idle self;
        int ret;
    CODE:
        Newx(self, 1, struct UV__Idle);
        ret = uv_idle_init(loop->loop, &self->idle);
        if (ret != 0) {
            Safefree(self);
            croak("Couldn't initialize idle handle (%d): %s", ret, uv_strerror(ret));
        }
        self->idle.data = self;

        INIT_UV_HANDLE_BASE(*self);
        self->on_idle = NULL;

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Idle", self);
        self->base.selfrv = SvRV(RETVAL); /* no inc */
    OUTPUT:
        RETVAL

SV *
_on_idle(UV::Idle self, SV *cb = NULL)
    CODE:
        RETVAL = do_callback_accessor(&self->on_idle, cb);
    OUTPUT:
        RETVAL

int
_start(UV::Idle self)
    CODE:
        RETVAL = uv_idle_start(&self->idle, on_idle_cb);
    OUTPUT:
        RETVAL

int
stop(UV::Idle self)
    CODE:
        RETVAL = uv_idle_stop(&self->idle);
    OUTPUT:
        RETVAL

MODULE = UV             PACKAGE = UV::Prepare

SV *
_new(char *class, UV::Loop loop)
    INIT:
        UV__Prepare self;
        int ret;
    CODE:
        Newx(self, 1, struct UV__Prepare);
        ret = uv_prepare_init(loop->loop, &self->prepare);
        if (ret != 0) {
            Safefree(self);
            croak("Couldn't initialize prepare handle (%d): %s", ret, uv_strerror(ret));
        }
        self->prepare.data = self;

        INIT_UV_HANDLE_BASE(*self);
        self->on_prepare = NULL;

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Prepare", self);
        self->base.selfrv = SvRV(RETVAL); /* no inc */
    OUTPUT:
        RETVAL

SV *
_on_prepare(UV::Prepare self, SV *cb = NULL)
    CODE:
        RETVAL = do_callback_accessor(&self->on_prepare, cb);
    OUTPUT:
        RETVAL

int
_start(UV::Prepare self)
    CODE:
        RETVAL = uv_prepare_start(&self->prepare, on_prepare_cb);
    OUTPUT:
        RETVAL

int
stop(UV::Prepare self)
    CODE:
        RETVAL = uv_prepare_stop(&self->prepare);
    OUTPUT:
        RETVAL

MODULE = UV             PACKAGE = UV::Poll

SV *
_new(char *class, UV::Loop loop, int fd, bool is_socket)
    INIT:
        UV__Poll self;
        int ret;
    CODE:
        Newx(self, 1, struct UV__Poll);
        if(is_socket)
            ret = uv_poll_init_socket(loop->loop, &self->poll, _MAKE_SOCK(fd));
        else
            ret = uv_poll_init(loop->loop, &self->poll, fd);
        if (ret != 0) {
            Safefree(self);
            croak("Couldn't initialize poll handle (%d): %s", ret, uv_strerror(ret));
        }
        self->poll.data = self;

        INIT_UV_HANDLE_BASE(*self);
        self->on_poll = NULL;

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Poll", self);
        self->base.selfrv = SvRV(RETVAL); /* no inc */
    OUTPUT:
        RETVAL

SV *
_on_poll(UV::Poll self, SV *cb = NULL)
    CODE:
        RETVAL = do_callback_accessor(&self->on_poll, cb);
    OUTPUT:
        RETVAL

int
_start(UV::Poll self, int events = UV_READABLE)
    CODE:
        RETVAL = uv_poll_start(&self->poll, events, on_poll_cb);
    OUTPUT:
        RETVAL

int
stop(UV::Poll self)
    CODE:
        RETVAL = uv_poll_stop(&self->poll);
    OUTPUT:
        RETVAL

MODULE = UV             PACKAGE = UV::Signal

SV *
_new(char *class, UV::Loop loop, int signum)
    INIT:
        UV__Signal self;
        int ret;
    CODE:
        Newx(self, 1, struct UV__Signal);
        ret = uv_signal_init(loop->loop, &self->signal);
        if (ret != 0) {
            Safefree(self);
            croak("Couldn't initialise signal handle (%d): %s", ret, uv_strerror(ret));
        }
        self->signal.data = self;
        self->signum = signum; /* need to remember this until start() time */

        INIT_UV_HANDLE_BASE(*self);
        self->on_signal = NULL;

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Signal", self);
        self->base.selfrv = SvRV(RETVAL); /* no inc */
    OUTPUT:
        RETVAL

SV *
_on_signal(UV::Signal self, SV *cb = NULL)
    CODE:
        RETVAL = do_callback_accessor(&self->on_signal, cb);
    OUTPUT:
        RETVAL

int
_start(UV::Signal self)
    CODE:
        RETVAL = uv_signal_start(&self->signal, on_signal_cb, self->signum);
    OUTPUT:
        RETVAL

int
stop(UV::Signal self)
    CODE:
        RETVAL = uv_signal_stop(&self->signal);

MODULE = UV             PACKAGE = UV::Timer

SV *
_new(char *class, UV::Loop loop)
    INIT:
        UV__Timer self;
        int ret;
    CODE:
        Newx(self, 1, struct UV__Timer);
        ret = uv_timer_init(loop->loop, &self->timer);
        if (ret != 0) {
            Safefree(self);
            croak("Couldn't initialize timer handle (%d): %s", ret, uv_strerror(ret));
        }
        self->timer.data = self;

        INIT_UV_HANDLE_BASE(*self);
        self->on_timer = NULL;

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, "UV::Timer", self);
        self->base.selfrv = SvRV(RETVAL); /* no inc */
    OUTPUT:
        RETVAL

SV *
_on_timer(UV::Timer self, SV *cb = NULL)
    CODE:
        RETVAL = do_callback_accessor(&self->on_timer, cb);
    OUTPUT:
        RETVAL

int
_start(UV::Timer self, UV timeout, UV repeat)
    CODE:
        RETVAL = uv_timer_start(&self->timer, on_timer_cb, timeout, repeat);
    OUTPUT:
        RETVAL

UV
_get_repeat(UV::Timer self)
    CODE:
        RETVAL = uv_timer_get_repeat(&self->timer);
    OUTPUT:
        RETVAL

void
_set_repeat(UV::Timer self, UV repeat)
    CODE:
        uv_timer_set_repeat(&self->timer, repeat);

int
again(UV::Timer self)
    CODE:
        RETVAL = uv_timer_again(&self->timer);
    OUTPUT:
        RETVAL

int
stop(UV::Timer self)
    CODE:
        RETVAL = uv_timer_stop(&self->timer);
    OUTPUT:
        RETVAL

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

void
_walk(UV::Loop self)
    CODE:
        uv_walk(self->loop, on_loop_walk, self->on_walk);

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
