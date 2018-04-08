#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define MATH_INT64_NATIVE_IF_AVAILABLE
#include "perl_math_int64.h"
#include <assert.h>
#include <stdlib.h>

#include <uv.h>
#include "p5uv_constants.h"
#include "p5uv_loops_handles.h"

#if defined(_WIN32_WINNT)
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <io.h> /* we need _get_osfhandle() on windows */
#define _MAKE_SOCK(s, f) s = _get_osfhandle(f)
#else
#define _MAKE_SOCK(s,f) s = f
#endif

/* store the singleton default_loop. not thread-safe */
static uv_loop_t *default_loop;
static uv_loop_t* get_loop_singleton(pTHX_ SV *class)
{
    loop_data_t *data_ptr;
    if (!default_loop) {
        default_loop = loop_new(aTHX_ class, 1);
    }
    data_ptr = loop_data(default_loop);
    data_ptr->is_default = 1;
    return default_loop;
}

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


MODULE = UV             PACKAGE = UV::Loop      PREFIX = p5uv_loop_

PROTOTYPES: ENABLE

SV *p5uv_loop__construct(SV *class)
    CODE:
    uv_loop_t *loop;
    loop = loop_new(aTHX_ class, 0);
    RETVAL = loop_bless(aTHX_ loop);
    OUTPUT:
    RETVAL

SV *p5uv_loop__singleton(SV *class)
    CODE:
        RETVAL = loop_bless(aTHX_ get_loop_singleton(aTHX_ class));
    OUTPUT:
    RETVAL

SV *p5uv_loop__callbacks(uv_loop_t *loop)
    CODE:
    loop_data_t *data_ptr;
    RETVAL = &PL_sv_undef;
    if (loop) {
        data_ptr = (loop_data_t *)(loop->data);
        if (data_ptr) {
            RETVAL = newRV_inc((SV *)(data_ptr->callbacks));
        }
    }
    OUTPUT:
    RETVAL

SV *p5uv_loop__events(uv_loop_t *loop)
    CODE:
    loop_data_t *data_ptr;
    RETVAL = &PL_sv_undef;
    if (loop) {
        data_ptr = (loop_data_t *)(loop->data);
        if (data_ptr) {
            RETVAL = newRV_inc( (SV *)(data_ptr->events) );
        }
    }
    OUTPUT:
    RETVAL

void p5uv_loop__walk(uv_loop_t *loop)
    INIT:
        SV **callback;
        loop_data_t *data_ptr;
        SV *cb;
    CODE:
        if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");

        if (!loop || !loop->data) return;
        data_ptr = loop_data(loop);

        cb = NULL;
        callback = hv_fetchs(data_ptr->callbacks, "on_walk", FALSE);
        if (callback && SvOK(*callback)) cb = *callback;
        uv_walk(loop, loop_walk_cb, (void *)cb);

void DESTROY (uv_loop_t *loop)
    CODE:
    loop_data_t *data_ptr;
    if (!loop) return;
    data_ptr = loop_data(loop);
    if (data_ptr) {
        /* 1. the default loop shouldn't be freed by destroying it's perl loop object */
        /* 2. not doing so helps avoid many global destruction bugs in perl, too */
        if (data_ptr->is_default) {
            if (PL_dirty) {
                if (0 != uv_loop_alive(loop)) {
                    uv_walk(loop, loop_walk_close_cb, NULL);
                    uv_run(loop, UV_RUN_DEFAULT);
                    uv_loop_close(loop);
                }
                loop_data_destroy(aTHX_ data_ptr);
                loop->data = NULL;
            }
        }
        else {
            if (0 != uv_loop_alive(loop)) {
                uv_walk(loop, loop_walk_close_cb, NULL);
                uv_run(loop, UV_RUN_DEFAULT);
                uv_loop_close(loop);
            }
            loop_data_destroy(aTHX_ data_ptr);
            loop->data = NULL;
            Safefree(loop);
        }
    }

int p5uv_loop_is_default(const uv_loop_t* loop)
    CODE:
        RETVAL=loop_is_default(aTHX_ loop);
    OUTPUT:
    RETVAL

int p5uv_loop_backend_fd(const uv_loop_t* loop)
    CODE:
        if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");
        RETVAL=uv_backend_fd(loop);
    OUTPUT:
    RETVAL

int p5uv_loop_backend_timeout(const uv_loop_t* loop)
    CODE:
        if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");
        RETVAL = uv_backend_timeout(loop);
    OUTPUT:
    RETVAL

int p5uv_loop_close(uv_loop_t *loop)
    CODE:
        int res = UV_EBUSY;
        loop_data_t *data_ptr = loop_data(loop);
        if (loop && data_ptr) {
            res = uv_loop_close(loop);
            if (res == 0) {
                loop->data = NULL;
                data_ptr->closed = 1;
                if (data_ptr->is_default) {
                    default_loop = NULL;
                }
                loop_data_destroy(aTHX_ data_ptr);
            }
        }
        RETVAL = res;
    OUTPUT:
    RETVAL

int p5uv_loop_closed(uv_loop_t *loop)
    CODE:
        RETVAL = loop_closed(aTHX_ loop);
    OUTPUT:
    RETVAL

int p5uv_loop_alive(const uv_loop_t* loop)
    CODE:
        RETVAL = 0;
        if (!loop_closed(aTHX_ loop)) RETVAL = uv_loop_alive(loop);
    OUTPUT:
    RETVAL

int p5uv_loop_configure(uv_loop_t *loop, uv_loop_option option, int value)
    CODE:
    if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");
    RETVAL = uv_loop_configure(loop, option, value);
    OUTPUT:
    RETVAL

uint64_t p5uv_loop_now(const uv_loop_t* loop)
    CODE:
        if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");
        RETVAL=uv_now(loop);
    OUTPUT:
    RETVAL

int p5uv_loop_run(uv_loop_t* loop, uv_run_mode mode=UV_RUN_DEFAULT)
    CODE:
        if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");
        RETVAL = uv_run(loop, mode);
    OUTPUT:
    RETVAL

void p5uv_loop_stop(uv_loop_t* loop)
    CODE:
    if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");
    uv_stop(loop);

void p5uv_loop_update_time(uv_loop_t* loop)
    CODE:
    if (loop_closed(aTHX_ loop)) Perl_croak(aTHX_ "Can't operate on a closed loop.");
    uv_update_time(loop);

MODULE = UV             PACKAGE = UV::Handle      PREFIX = p5uv_handle_

PROTOTYPES: ENABLE

void p5uv_handle__destruct(uv_handle_t *handle)
    CODE:
    handle_data_t *data_ptr;
    if (handle) {
        data_ptr = (handle_data_t *)(handle->data);
        if (!data_ptr || data_ptr->closed) {
            /* We can destroy here if we have nothing to close */
            handle_data_destroy(aTHX_ data_ptr);
            handle->data = NULL;
            Safefree(handle);
        }
        else if (!uv_is_closing(handle)) {
            /* this particular handle close CB will destroy when done */
            uv_close(handle, handle_close_destroy_cb);
        }
    }

SV *p5uv_handle__callbacks(uv_handle_t *handle)
    CODE:
    handle_data_t *data_ptr;
    RETVAL = &PL_sv_undef;
    if (handle) data_ptr = handle_data(handle);

    if (handle && data_ptr) {
        RETVAL = newRV_inc((SV *)(data_ptr->callbacks));
    }
    OUTPUT:
    RETVAL

void p5uv_handle__close(uv_handle_t *handle)
    CODE:
    uv_close(handle, handle_close_cb);

SV *p5uv_handle__events(uv_handle_t *handle)
    CODE:
    handle_data_t *data_ptr;
    RETVAL = &PL_sv_undef;
    if (handle) data_ptr = handle_data(handle);

    if (handle && data_ptr) {
        RETVAL = newRV_inc((SV *)(data_ptr->events));
    }
    OUTPUT:
    RETVAL

SV *p5uv_handle_loop(uv_handle_t *handle)
    CODE:
    RETVAL = loop_bless(aTHX_ handle->loop);
    OUTPUT:
    RETVAL

int p5uv_handle_active(uv_handle_t *handle)
    ALIAS:
        UV::Handle::is_active = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = uv_is_active(handle);
    OUTPUT:
    RETVAL

int p5uv_handle_closing(uv_handle_t *handle)
    CODE:
        RETVAL = uv_is_closing(handle);
    OUTPUT:
    RETVAL

int p5uv_handle_closed(uv_handle_t *handle)
    CODE:
        RETVAL = handle_closed(aTHX_ handle);
    OUTPUT:
    RETVAL

SV * p5uv_handle_data(uv_handle_t *handle, SV *new_val = NULL)
    CODE:
        handle_data_t *data_ptr = handle_data(handle);
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
            RETVAL = handle_bless(aTHX_ handle);
        }
    OUTPUT:
    RETVAL

int p5uv_handle_has_ref(uv_handle_t *handle)
    CODE:
        RETVAL = uv_has_ref(handle);
    OUTPUT:
    RETVAL

void p5uv_handle_ref(uv_handle_t *handle)
    CODE:
    uv_ref(handle);

int p5uv_handle_type(uv_handle_t *handle)
    CODE:
    RETVAL = handle->type;
    OUTPUT:
    RETVAL

void p5uv_handle_unref(uv_handle_t *handle)
    CODE:
    uv_unref(handle);


MODULE = UV             PACKAGE = UV::Check      PREFIX = p5uv_check_

PROTOTYPES: ENABLE

SV * p5uv_check__construct(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    handle_data_t *data_ptr;
    uv_check_t *handle = (uv_check_t *)handle_new(aTHX_ class, UV_CHECK);
    if (!loop) loop = get_loop_singleton(aTHX_ newSVpv("UV::Loop", 8));

    res = uv_check_init(loop, handle);
    if (0 != res) {
        handle_destroy(aTHX_ (uv_handle_t *)handle);
        croak("Couldn't initialize check (%i): %s", res, uv_strerror(res));
    }
    data_ptr = handle_data(handle);
    av_push(data_ptr->events, newSVpv("check", 0));
    hv_store(data_ptr->callbacks, "on_check", 8, newSV(0), 0);

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

int p5uv_check__start(uv_check_t *handle)
    CODE:
        RETVAL = uv_check_start(handle, handle_check_cb);
    OUTPUT:
    RETVAL

int p5uv_check_stop(uv_check_t *handle)
    CODE:
        RETVAL = uv_check_stop(handle);
    OUTPUT:
    RETVAL


MODULE = UV             PACKAGE = UV::Idle      PREFIX = p5uv_idle_

PROTOTYPES: ENABLE

SV * p5uv_idle__construct(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    handle_data_t *data_ptr;
    uv_idle_t *handle = (uv_idle_t *)handle_new(aTHX_ class, UV_IDLE);
    if (!loop) loop = get_loop_singleton(aTHX_ newSVpv("UV::Loop", 8));

    res = uv_idle_init(loop, handle);
    if (0 != res) {
        handle_destroy(aTHX_ (uv_handle_t *)handle);
        croak("Couldn't initialize idle (%i): %s", res, uv_strerror(res));
    }
    data_ptr = handle_data(handle);
    av_push(data_ptr->events, newSVpv("idle", 0));
    hv_store(data_ptr->callbacks, "on_idle", 7, newSV(0), 0);

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

int p5uv_idle__start(uv_idle_t *handle)
    CODE:
        handle_data_t *data_ptr = handle_data(handle);
        if (data_ptr->closed || uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        RETVAL = uv_idle_start(handle, handle_idle_cb);
    OUTPUT:
    RETVAL

int p5uv_idle_stop(uv_idle_t *handle)
    CODE:
        RETVAL = uv_idle_stop(handle);
    OUTPUT:
    RETVAL


MODULE = UV             PACKAGE = UV::Poll      PREFIX = p5uv_poll_

PROTOTYPES: ENABLE

SV * p5uv_poll__construct(SV *class, int fd, uv_loop_t *loop = NULL)
    CODE:
    int res;
    handle_data_t *data_ptr;
    uv_poll_t *handle = (uv_poll_t *)handle_new(aTHX_ class, UV_POLL);

    if (!loop) loop = get_loop_singleton(aTHX_ newSVpv("UV::Loop", 8));
    res = uv_poll_init_socket(loop, handle, (uv_os_sock_t)fd);
    if (0 != res) {
        handle_destroy(aTHX_ (uv_handle_t *)handle);
        croak("Couldn't initialize handle (%i): %s", res, uv_strerror(res));
    }
    data_ptr = handle_data(handle);
    av_push(data_ptr->events, newSVpv("poll", 0));
    hv_store(data_ptr->callbacks, "on_poll", 7, newSV(0), 0);

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

int p5uv_poll__start(uv_poll_t *handle, int events = UV_READABLE)
    CODE:
        handle_data_t *data_ptr = handle_data(handle);
        if (data_ptr->closed || uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        RETVAL = uv_poll_start(handle, events, handle_poll_cb);
    OUTPUT:
    RETVAL

int p5uv_poll_stop(uv_poll_t *handle)
    CODE:
        RETVAL = uv_poll_stop(handle);
    OUTPUT:
    RETVAL



MODULE = UV             PACKAGE = UV::Prepare      PREFIX = p5uv_prepare_

PROTOTYPES: ENABLE

SV * p5uv_prepare__construct(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    handle_data_t *data_ptr;
    uv_prepare_t *handle = (uv_prepare_t *)handle_new(aTHX_ class, UV_PREPARE);
    if (!loop) loop = get_loop_singleton(aTHX_ newSVpv("UV::Loop", 8));

    res = uv_prepare_init(loop, handle);
    if (0 != res) {
        handle_destroy(aTHX_ (uv_handle_t *)handle);
        croak("Couldn't initialize prepare (%i): %s", res, uv_strerror(res));
    }

    data_ptr = handle_data(handle);
    av_push(data_ptr->events, newSVpv("prepare", 0));
    hv_store(data_ptr->callbacks, "on_prepare", 10, newSV(0), 0);

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

int p5uv_prepare__start(uv_prepare_t *handle)
    CODE:
        handle_data_t *data_ptr = handle_data(handle);
        if (data_ptr->closed || uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        RETVAL = uv_prepare_start(handle, handle_prepare_cb);
    OUTPUT:
    RETVAL

int p5uv_prepare_stop(uv_prepare_t *handle)
    CODE:
        RETVAL = uv_prepare_stop(handle);
    OUTPUT:
    RETVAL



MODULE = UV             PACKAGE = UV::Timer      PREFIX = p5uv_timer_

PROTOTYPES: ENABLE

SV * p5uv_timer__construct(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    handle_data_t *data_ptr;
    uv_timer_t *handle = (uv_timer_t *)handle_new(aTHX_ class, UV_TIMER);
    if (!loop) loop = get_loop_singleton(aTHX_ newSVpv("UV::Loop", 8));
    res = uv_timer_init(loop, handle);
    if (0 != res) {
        handle_destroy(aTHX_ (uv_handle_t *)handle);
        croak("Couldn't initialize timer (%i): %s", res, uv_strerror(res));
    }
    data_ptr = handle_data(handle);
    av_push(data_ptr->events, newSVpv("timer", 0));
    hv_store(data_ptr->callbacks, "on_timer", 8, newSV(0), 0);

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

uint64_t p5uv_timer__get_repeat(uv_timer_t *handle)
    CODE:
        RETVAL = uv_timer_get_repeat(handle);
    OUTPUT:
    RETVAL

void p5uv_timer__set_repeat(uv_timer_t *handle, uint64_t repeat)
    CODE:
        uv_timer_set_repeat(handle, repeat);

int p5uv_timer__start(uv_timer_t *handle, uint64_t start=0, uint64_t repeat=0)
    CODE:
        handle_data_t *data_ptr = handle_data(handle);
        if (data_ptr->closed || uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        RETVAL = uv_timer_start(handle, handle_timer_cb, start, repeat);
    OUTPUT:
    RETVAL

int p5uv_timer_again(uv_timer_t *handle)
    CODE:
        RETVAL = uv_timer_again(handle);
    OUTPUT:
    RETVAL

int p5uv_timer_stop(uv_timer_t *handle)
    CODE:
        RETVAL = uv_timer_stop(handle);
    OUTPUT:
    RETVAL
