#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"

#define MATH_INT64_NATIVE_IF_AVAILABLE
#include "perl_math_int64.h"
#include <assert.h>
#include <stdlib.h>

#include <uv.h>
#include "p5uv_constants.h"

#define handle_data(h)      ((handle_data_t *)((uv_handle_t *)(h))->data)

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
    SV *poll_cb;
    SV *prepare_cb;
    SV *timer_cb;
} handle_data_t;

static struct UVAPI uvapi;
static SV *default_loop_sv;

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
static void handle_idle_cb(uv_idle_t* handle);
static const char* handle_namespace(const uv_handle_type type);
static void handle_poll_cb(uv_poll_t* handle, int status, int events);
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
            gv_stashpv("UV::Loop", GV_ADD)
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
    data_ptr = NULL;
}

static handle_data_t* handle_data_new(const uv_handle_type type)
{
    handle_data_t *data_ptr = (handle_data_t *)malloc(sizeof(handle_data_t));
    if (NULL == data_ptr) {
        croak("Cannot allocate space for handle data.");
    }

    /* set the stash */
    data_ptr->stash = gv_stashpv(handle_namespace(type), GV_ADD);
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
    data_ptr->poll_cb = NULL;
    data_ptr->prepare_cb = NULL;
    data_ptr->timer_cb = NULL;
    return data_ptr;
}

static void handle_destroy(uv_handle_t *handle)
{
    if (NULL == handle) return;
    if (0 == uv_is_closing(handle) && 0 == uv_is_active(handle)) {
        uv_close(handle, handle_close_cb);
        handle_data_destroy(handle_data(handle));
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

static const char * handle_namespace(const uv_handle_type type)
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

static void handle_on(uv_handle_t *handle, const char *name, SV *cb)
{
    SV *callback = NULL;
    handle_data_t *data_ptr = handle_data(handle);
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
static void handle_alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf)
{
    handle_data_t *data_ptr = handle_data(handle);
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
    handle_data_t *data_ptr = handle_data(handle);

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
    handle_data_t *data_ptr = handle_data(handle);

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
    handle_data_t *data_ptr = handle_data(handle);
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

static void handle_poll_cb(uv_poll_t* handle, int status, int events)
{
    handle_data_t *data_ptr = handle_data(handle);

    /* nothing else to do if we don't have a callback to call */
    if (NULL == data_ptr || NULL == data_ptr->poll_cb) return;

    /* provide info to the caller: invocant, status, events */
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK (SP);
    EXTEND (SP, 3);
    PUSHs(handle_bless((uv_handle_t *)handle)); /* invocant */
    mPUSHi(status);
    mPUSHi(events);

    PUTBACK;
    call_sv (data_ptr->poll_cb, G_VOID);
    SPAGAIN;

    FREETMPS;
    LEAVE;
}

static void handle_prepare_cb(uv_prepare_t* handle)
{
    handle_data_t *data_ptr = handle_data(handle);
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
    handle_data_t *data_ptr = handle_data(handle);
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
    constants_export_uv();

    /* somewhat of an API */
    uvapi.default_loop = NULL;
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
    constants_export_uv_handle();
}

void DESTROY(uv_handle_t *handle)
    CODE:
    handle_destroy(handle);

SV *uv_handle_loop(uv_handle_t *handle)
    CODE:
    RETVAL = newSVsv(handle_data(handle)->loop_sv);
    OUTPUT:
    RETVAL

int uv_handle_active (uv_handle_t *handle)
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
        handle_on(handle, "close", cb);
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
        handle_data(handle)->loop_sv = default_loop_sv;
    }
    else {
        handle_data(handle)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), gv_stashpv("UV::Loop", GV_ADD));
    }
    RETVAL = handle_bless((uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_check_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_check_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(handle_data(handle));
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
        handle_data(handle)->loop_sv = default_loop_sv;
    }
    else {
        handle_data(handle)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), gv_stashpv("UV::Loop", GV_ADD));
    }
    RETVAL = handle_bless((uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_idle_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_idle_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(handle_data(handle));
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



MODULE = UV             PACKAGE = UV::Poll      PREFIX = uv_poll_

PROTOTYPES: ENABLE

BOOT:
{
    constants_export_uv_poll();
}

SV * uv_poll_new(SV *class, int fd, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_poll_t *handle = (uv_poll_t *)handle_new(UV_POLL);
    PERL_UNUSED_VAR(class);
    loop_default_init();
    if (NULL == loop) loop = uvapi.default_loop;

    res = uv_poll_init(loop, handle, fd);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize handle (%i): %s", res, uv_strerror(res));
    }

    if (loop == uvapi.default_loop) {
        handle_data(handle)->loop_sv = default_loop_sv;
    }
    else {
        handle_data(handle)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), gv_stashpv("UV::Loop", GV_ADD));
    }
    RETVAL = handle_bless((uv_handle_t *)handle);
    OUTPUT:
    RETVAL

SV * uv_poll_new_socket(SV *class, int fd, uv_loop_t *loop = NULL)
    CODE:
    int res;
    uv_poll_t *handle = (uv_poll_t *)handle_new(UV_POLL);
    PERL_UNUSED_VAR(class);
    loop_default_init();
    if (NULL == loop) loop = uvapi.default_loop;

    res = uv_poll_init_socket(loop, handle, fd);
    if (0 != res) {
        Safefree(handle);
        croak("Couldn't initialize handle (%i): %s", res, uv_strerror(res));
    }

    if (loop == uvapi.default_loop) {
        handle_data(handle)->loop_sv = default_loop_sv;
    }
    else {
        handle_data(handle)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), gv_stashpv("UV::Loop", GV_ADD));
    }
    RETVAL = handle_bless((uv_handle_t *)handle);
    OUTPUT:
    RETVAL

void DESTROY(uv_poll_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_poll_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(handle_data(handle));
    }

int uv_poll_start(uv_poll_t *handle, int events = UV_READABLE, SV *cb=NULL)
    CODE:
        if (uv_is_closing((uv_handle_t *)handle)) {
            croak("You can't call start on a closed handle");
        }
        if (items > 2) {
            cb = cb == &PL_sv_undef ? NULL : cb;
            handle_on((uv_handle_t *)handle, "poll", cb);
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
        handle_data(prepare)->loop_sv = default_loop_sv;
    }
    else {
        handle_data(prepare)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), gv_stashpv("UV::Loop", GV_ADD));
    }
    RETVAL = handle_bless((uv_handle_t *)prepare);
    OUTPUT:
    RETVAL

void DESTROY(uv_prepare_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_prepare_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(handle_data(handle));
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
        handle_data(timer)->loop_sv = default_loop_sv;
    }
    else {
        handle_data(timer)->loop_sv = sv_bless( newRV_noinc( newSViv( PTR2IV(loop))), gv_stashpv("UV::Loop", GV_ADD));
    }
    RETVAL = handle_bless((uv_handle_t *)timer);
    OUTPUT:
    RETVAL

void DESTROY(uv_timer_t *handle)
    CODE:
    if (NULL != handle && 0 == uv_is_closing((uv_handle_t *)handle) && 0 == uv_is_active((uv_handle_t *)handle)) {
        uv_timer_stop(handle);
        uv_close((uv_handle_t *)handle, handle_close_cb);
        handle_data_destroy(handle_data(handle));
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
    constants_export_uv_loop();
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
            ), gv_stashpv("UV::Loop", GV_ADD)
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
