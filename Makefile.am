
# These files are not mentioned in any other Makefile
EXTRA_DIST = README 

SUBDIRS = lua docs testing examples

LUA              = @LUA@
MOD_NAME         = @MOD_NAME@
MOD_VERSION      = @MOD_VERSION@
LIB_VERSION      = @LIB_VERSION@
LUA_INSTALL_CMOD = @LUA_INSTALL_CMOD@
LUA_INSTALL_LMOD = @LUA_INSTALL_LMOD@
LUA_DEFINES      = @LUA_DEFINES@
LUA_CFLAGS       = @LUA_CFLAGS@
LUA_LFLAGS       = @LUA_LFLAGS@

AUTOMAKE_OPTIONS= foreign
ACLOCAL_M4= $(top_srcdir)/aclocal.m4

CLEANFILES = core.so

osbfdir=$(LUA_INSTALL_CMOD)/$(MOD_NAME)
fastmimedir=$(LUA_INSTALL_CMOD)

osbf_LTLIBRARIES = core.la
core_la_SOURCES = losbflib.c oarray.c oarray.h osbf_aux.c osbf_bayes.c \
                  osbf_csv.c osbfcvt.h osbf_disk.c osbf_disk.h osbferr.h \
                  osbferrl.c osbf_fmt_5.c osbf_fmt_6.c osbf_fmt_7.c \
                  osbflib.h osbf_stats.c
if USE_LOCKFILE
core_la_LIBADD = -llockfile -lm
else
core_la_LIBADD = -lm
endif

core_la_LDFLAGS = -module -version-info $(LIB_VERSION) $(LUA_LFLAGS)
core_la_CFLAGS = $(LUA_CFLAGS) $(LUA_DEFINES) -DMOD_VERSION=\"$(MOD_VERSION)\" \
                 -g -fno-optimize-sibling-calls -DOPENFUN=luaopen_$(MOD_NAME)_core

fastmime_LTLIBRARIES = fastmime.la
fastmime_la_SOURCES = fastmime.c
fastmime_la_LDFLAGS = -module $(LUA_LFLAGS)
fastmime_la_CFLAGS  =  $(LUA_CFLAGS) $(LUA_DEFINES) -g -fno-optimize-sibling-calls \
                      -DOPENFUN=luaopen_$(MOD_NAME)_core

msg_test:
	case `hostname` in \
	  labrador*)  cp /home/nr/Mail/fidelis-assis/44 msg_test ;; \
	  *) cp sample.msg test_msg ;; \
	esac

test: msg_test
	$(LUA) -l$(MOD_NAME) -l$(MOD_NAME).command_line ./print-contents $(MOD_NAME)
	$(LUA) -l$(MOD_NAME) -l$(MOD_NAME).roc < /dev/null
	$(LUA) -l$(MOD_NAME) -l$(MOD_NAME).mlearn < /dev/null
	$(LUA) ./test-headers $(MOD_NAME) msg_test
	$(LUA) -l$(MOD_NAME) -e "m = $(MOD_NAME).cache.msg_of_any 'msg_test'; print(m)" -i

