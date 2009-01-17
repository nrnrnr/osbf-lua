## Process this file with automake to produce Makefile.in

# These files are not mentioned in any other Makefile
EXTRA_DIST = README 

SUBDIRS = lua docs testing examples examples-autoconfed

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

coreSOURCES = losbflib.c oarray.c oarray.h osbf_aux.c osbf_bayes.c \
              osbf_csv.c osbfcvt.h osbf_disk.c osbf_disk.h osbferr.h \
              osbferrl.c osbf_fmt_5.c osbf_fmt_6.c osbf_fmt_7.c \
              osbflib.h osbf_stats.c

osbf_LTLIBRARIES = core.la
core_la_SOURCES = $(coreSOURCES)
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
fastmime_la_CFLAGS  =  $(LUA_CFLAGS) $(LUA_DEFINES) -g \
                       -fno-optimize-sibling-calls \
                       -DOPENFUN=luaopen_$(MOD_NAME)_core

PROFLIBS = -ldl
LIBDEBUG = -L/usr/local/lua-5.1.2-dbg/lib -L/usr/lib/debug \
           -L/usr/lib/debug/usr/lib
PG=

check_PROGRAMS = osbf-lua #mem-test
if USE_LOCKFILE
osbf_lua_LDADD = -llockfile -lreadline -lhistory -lncurses -lm 
#mem_test_LDADD = -llockfile -lreadline -lhistory -lncurses -lm 
else
osbf_lua_LDADD = -lreadline -lhistory -lncurses -lm
#mem_test_LDADD = -lreadline -lhistory -lncurses -lm
endif
osbf_lua_SOURCES = $(coreSOURCES) fastmime.c lua.c main.c
osbf_lua_CFLAGS = $(LUA_CFLAGS) $(LUA_DEFINES) \
                  -DMOD_VERSION=\"$(MOD_VERSION)\" -g \
		  -Wall -Werror \
                  -fno-optimize-sibling-calls \
                  -DOPENFUN=luaopen_$(MOD_NAME)_core
osbf_lua_LDFLAGS = $(LUA_LFLAGS) $(LIBDEBUG) $(PG) $(PROFLIBS)

#mem_test_SOURCES = small.c lua.c main.c
#mem_test_CFLAGS = $(LUA_CFLAGS) $(LUA_DEFINES) \
#                  -DMOD_VERSION=\"$(MOD_VERSION)\" -g \
#                  -fno-optimize-sibling-calls \
#                  -DOPENFUN=luaopen_$(MOD_NAME)_core
#mem_test_LDFLAGS = $(LUA_LFLAGS) $(LIBDEBUG) $(PG) $(PROFLIBS)

msg_test:
	case `hostname` in \
	  labrador*)  cp /home/nr/Mail/fidelis-assis/44 msg_test ;; \
	  *) cp sample.msg msg_test ;; \
	esac

test: msg_test
	$(LUA) -l$(MOD_NAME) -l$(MOD_NAME).command_line ./print-contents $(MOD_NAME)
	$(LUA) -l$(MOD_NAME) -l$(MOD_NAME).roc < /dev/null
	$(LUA) -l$(MOD_NAME) -l$(MOD_NAME).mlearn < /dev/null
	$(LUA) ./test-headers $(MOD_NAME) msg_test
	$(LUA) -l$(MOD_NAME) -e "m = $(MOD_NAME).cache.msg_of_any 'msg_test'; print(m)" -i

