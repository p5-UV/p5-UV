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


MODULE = UV             PACKAGE = UV            PREFIX = uv_

PROTOTYPES: ENABLE

BOOT:
{
    PERL_MATH_INT64_LOAD_OR_CROAK;
    constants_export_uv(aTHX);
}

const char* uv_err_name(int err)

uint64_t uv_hrtime()

const char* uv_strerror(int err)

unsigned int uv_version()

const char* uv_version_string()


MODULE = UV             PACKAGE = UV::Handle      PREFIX = uv_handle_

PROTOTYPES: ENABLE

BOOT:
{
    constants_export_uv_handle(aTHX);
}

void DESTROY(uv_handle_t *handle)
    CODE:
    handle_destroy(aTHX_ handle);

SV *uv_handle_loop(uv_handle_t *handle)
    CODE:
    RETVAL = loop_bless(aTHX_ handle->loop);
    OUTPUT:
    RETVAL

int uv_handle_active(uv_handle_t *handle)
    ALIAS:
        UV::Handle::is_active = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = uv_is_active(handle);
    OUTPUT:
    RETVAL

int uv_handle_closing(uv_handle_t *handle)
    ALIAS:
        UV::Handle::is_closing = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = uv_is_closing(handle);
    OUTPUT:
    RETVAL

void uv_handle_close(uv_handle_t *handle, SV *cb=NULL)
    CODE:
    if (items > 1) {
        cb = cb == &PL_sv_undef ? NULL : cb;
        handle_on(aTHX_ handle, "close", cb);
    }
    uv_close(handle, handle_close_cb);

SV * uv_handle_data(uv_handle_t *handle, SV *new_val = NULL)
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

int uv_handle_has_ref(uv_handle_t *handle)
    CODE:
        RETVAL = uv_has_ref(handle);
    OUTPUT:
    RETVAL

void uv_handle_on(uv_handle_t *handle, const char *name, SV *cb=NULL)
    CODE:
    cb = cb == &PL_sv_undef ? NULL : cb;
    handle_on(aTHX_ handle, name, cb);

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

SV * uv_check_new(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_check_t *handle = (uv_check_t *)handle_new(aTHX_ UV_CHECK);
    PERL_UNUSED_VAR(class);
    if (!loop) loop = loop_default(aTHX);

    res = uv_check_init(loop, handle);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize check (%i): %s", res, uv_strerror(res));
    }

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_check_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_check_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(aTHX_ handle_data(handle));
        handle->data = NULL;
    }

int uv_check_start(uv_check_t *handle, SV *cb=NULL)
    CODE:
        if (items > 1) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on(aTHX_ (uv_handle_t *)handle, "check", cb);
        }
        RETVAL = uv_check_start(handle, handle_check_cb);
    OUTPUT:
    RETVAL

int uv_check_stop(uv_check_t *handle)



MODULE = UV             PACKAGE = UV::Idle      PREFIX = uv_idle_

PROTOTYPES: ENABLE

SV * uv_idle_new(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_idle_t *handle = (uv_idle_t *)handle_new(aTHX_ UV_IDLE);
    PERL_UNUSED_VAR(class);
    if (!loop) loop = loop_default(aTHX);

    res = uv_idle_init(loop, handle);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize idle (%i): %s", res, uv_strerror(res));
    }

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_idle_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_idle_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(aTHX_ handle_data(handle));
        handle->data = NULL;
    }

int uv_idle_start(uv_idle_t *handle, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 1) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on(aTHX_ (uv_handle_t *)handle, "idle", cb);
        }
        RETVAL = uv_idle_start(handle, handle_idle_cb);
    OUTPUT:
    RETVAL

int uv_idle_stop(uv_idle_t *handle)



MODULE = UV             PACKAGE = UV::Poll      PREFIX = uv_poll_

PROTOTYPES: ENABLE

BOOT:
{
    constants_export_uv_poll(aTHX);
}

SV * uv_poll_new(SV *class, int fd, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_poll_t *handle = (uv_poll_t *)handle_new(aTHX_ UV_POLL);
    PERL_UNUSED_VAR(class);
    if (!loop) loop = loop_default(aTHX);

    res = uv_poll_init(loop, handle, fd);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize handle (%i): %s", res, uv_strerror(res));
    }

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

SV * uv_poll_new_socket(SV *class, int fd, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_poll_t *handle = (uv_poll_t *)handle_new(aTHX_ UV_POLL);
    PERL_UNUSED_VAR(class);
    if (!loop) loop = loop_default(aTHX);

    res = uv_poll_init_socket(loop, handle, fd);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize handle (%i): %s", res, uv_strerror(res));
    }

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_poll_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_poll_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(aTHX_ handle_data(handle));
        handle->data = NULL;
    }

int uv_poll_start(uv_poll_t *handle, int events = UV_READABLE, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 2) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on(aTHX_ (uv_handle_t *)handle, "poll", cb);
        }
        RETVAL = uv_poll_start(handle, events, handle_poll_cb);
    OUTPUT:
    RETVAL

int uv_poll_stop(uv_poll_t *handle)



MODULE = UV             PACKAGE = UV::Prepare      PREFIX = uv_prepare_

PROTOTYPES: ENABLE

SV * uv_prepare_new(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_prepare_t *prepare = (uv_prepare_t *)handle_new(aTHX_ UV_PREPARE);
    PERL_UNUSED_VAR(class);
    if (!loop) loop = loop_default(aTHX);

    res = uv_prepare_init(loop, prepare);
    if (0 != res) {
        Safefree(prepare);
        croak("Couldn't initialize prepare (%i): %s", res, uv_strerror(res));
    }

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)prepare);
    OUTPUT:
    RETVAL

void DESTROY(uv_prepare_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_prepare_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(aTHX_ handle_data(handle));
        handle->data = NULL;
    }

int uv_prepare_start(uv_prepare_t *handle, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 1) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on(aTHX_ (uv_handle_t *)handle, "prepare", cb);
        }
        RETVAL = uv_prepare_start(handle, handle_prepare_cb);
    OUTPUT:
    RETVAL

int uv_prepare_stop(uv_prepare_t *handle)



MODULE = UV             PACKAGE = UV::Timer      PREFIX = uv_timer_

PROTOTYPES: ENABLE

BOOT:
{
    PERL_MATH_INT64_LOAD_OR_CROAK;
}

SV * uv_timer_new(SV *class, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_timer_t *timer = (uv_timer_t *)handle_new(aTHX_ UV_TIMER);
    PERL_UNUSED_VAR(class);
    if (!loop) loop = loop_default(aTHX);
    res = uv_timer_init(loop, timer);
    if (0 != res) {
        Safefree(timer);
        croak("Couldn't initialize timer (%i): %s", res, uv_strerror(res));
    }

    RETVAL = handle_bless(aTHX_ (uv_handle_t *)timer);
    OUTPUT:
    RETVAL

void DESTROY(uv_timer_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_timer_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(aTHX_ handle_data(handle));
        handle->data = NULL;
    }

int uv_timer_again(uv_timer_t *handle)

int uv_timer_start(uv_timer_t *handle, uint64_t start=0, uint64_t repeat=0, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 3) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on(aTHX_ (uv_handle_t *)handle, "timer", cb);
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
    PERL_MATH_INT64_LOAD_OR_CROAK;
    constants_export_uv_loop(aTHX);
}

SV *new (SV *class, int want_default = 0)
    ALIAS:
        UV::Loop::default_loop = 1
        UV::Loop::default = 2
    CODE:
    uv_loop_t *loop;
    PERL_UNUSED_VAR(class);
    if (ix == 1 || ix == 2) want_default = 1;
    if (want_default) {
        loop = loop_default(aTHX);
    }
    else {
        loop = loop_new(aTHX);
    }
    loop_data_t *data_ptr = loop_data(loop);
    RETVAL = loop_bless(aTHX_ loop);
    OUTPUT:
    RETVAL

void DESTROY (uv_loop_t *loop)
    CODE:
    loop_data_t *data_ptr;
    if (!loop) return;
    data_ptr = (loop_data_t *)loop->data;

    /* 1. the default loop shouldn't be freed by destroying it's perl loop object */
    /* 2. not doing so helps avoid many global destruction bugs in perl, too */
    if (data_ptr->is_default) {
        if (PL_dirty) {
            if (0 == uv_loop_close(loop)) {
                if (data_ptr) loop_data_destroy(aTHX_ data_ptr);
                loop->data = NULL;
            }
        }
    }
    else {
        if (0 == uv_loop_close(loop)) {
            if (data_ptr) loop_data_destroy(aTHX_ data_ptr);
            loop->data = NULL;
            Safefree(loop);
        }
    }

int uv_backend_fd(const uv_loop_t* loop)

int uv_backend_timeout(const uv_loop_t* loop)

int uv_close(uv_loop_t *loop)
    CODE:
        RETVAL = uv_loop_close(loop);
    OUTPUT:
    RETVAL

int uv_alive(const uv_loop_t* loop)
    CODE:
    RETVAL = uv_loop_alive(loop);
    OUTPUT:
    RETVAL

int uv_loop_alive(const uv_loop_t* loop)

int uv_configure(uv_loop_t *loop, uv_loop_option option, int value)
    CODE:
    RETVAL = uv_loop_configure(loop, option, value);
    OUTPUT:
    RETVAL

int uv_loop_configure(uv_loop_t* loop, uv_loop_option option, int value)

uint64_t uv_now(const uv_loop_t* loop)

int uv_run(uv_loop_t* loop, uv_run_mode mode=UV_RUN_DEFAULT)

void uv_stop(uv_loop_t* loop)

void uv_update_time(uv_loop_t* loop)

void uv_walk(uv_loop_t *loop, SV *cb=NULL)
    CODE:
        cb = cb == &PL_sv_undef ? NULL : cb;
        uv_walk(loop, loop_walk_cb, (void *)cb);
