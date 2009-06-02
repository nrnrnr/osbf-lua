/*
 * See Copyright Notice in osbflib.h
 */

#include <setjmp.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>

#include "osbferr.h"

struct osbf_error_handler {
  jmp_buf env;
  char err_buf[1000];
};

const char *osbf_pcall(osbf_error_fun f, void *data) {
  OSBF_HANDLER h;
  h.err_buf[0] = '\0';
  if (setjmp(h.env)) {
    char *s = malloc(strlen(h.err_buf)+1);
    strcpy(s, h.err_buf);
    return s;
  } else {
    return NULL;
  }
  f(&h, data);
  return NULL;
}

int osbf_raise(OSBF_HANDLER *h, const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vsnprintf(h->err_buf, sizeof(h->err_buf), fmt, args);
  va_end(args);
  longjmp(h->env, 1);
  return 0;
}

int osbf_raise_unless(int p, OSBF_HANDLER *h, const char *fmt, ...) {
  if (!p) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(h->err_buf, sizeof(h->err_buf), fmt, args);
    va_end(args);
    longjmp(h->env, 1);
  }
  return 0;
}
