#if !defined (P5UV_LOOPS_H)
#define P5UV_LOOPS_H

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"
#include <uv.h>
#include "p5uv_handles.h"

#define loop_data(l)        ((loop_data_t *)((uv_loop_t *)(l))->data)

static SV * loop_get_cv_croak(SV *cb_sv)
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

/* data to store with a LOOP */
typedef struct loop_data_s {
    SV *self;
    int is_default;
} loop_data_t;

/* Loop function definitions */
extern SV* loop_bless(pTHX_ uv_loop_t *loop);
extern loop_data_t* loop_data_new(pTHX);
extern void loop_data_destroy(pTHX_ loop_data_t *data_ptr);
extern uv_loop_t* loop_default(pTHX);
extern uv_loop_t* loop_new(pTHX);
extern void loop_walk_cb(uv_handle_t* handle, void* arg);

/* loop functions */
SV* loop_bless(pTHX_ uv_loop_t *loop)
{
    loop_data_t *data_ptr = loop_data(loop);
    if (!data_ptr || !data_ptr->self) {
        croak("Couldn't get the loop data");
    }

    return newSVsv(data_ptr->self);
}

void loop_data_destroy(pTHX_ loop_data_t *data_ptr)
{
    if (NULL == data_ptr) return;

    /* cleanup self */
    if (NULL != data_ptr->self) {
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

void loop_walk_cb(uv_handle_t* handle, void* arg)
{
    SV *callback;
    if (NULL == arg || (SV *)arg == &PL_sv_undef) return;
    dTHX;
    callback = arg ? loop_get_cv_croak((SV *)arg) : NULL;
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

#endif
