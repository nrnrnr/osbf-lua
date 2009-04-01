<mkconfig
<mk.sharedlib


MODNAME=$MOD_NAME
LIBNAME=$MODNAME.so
BINNAME=osbf3  # probably should come from config

MAILFILE=`./mailfile`

HFILES= oarray.h osbf_disk.h osbfcvt.h osbferr.h osbflib.h
SRCS= losbflib.c osbferrl.c oarray.c \
      osbf_bayes.c osbf_aux.c osbf_disk.c osbf_csv.c osbf_stats.c \
      osbf_fmt_5.c osbf_fmt_6.c osbf_fmt_7.c fastmime.c
OBJS= losbflib.o osbferrl.o oarray.o \
      osbf_bayes.o osbf_aux.o osbf_disk.o osbf_csv.o osbf_stats.o \
      osbf_fmt_5.o osbf_fmt_6.o osbf_fmt_7.o fastmime.o
XOBJS= osbferrs.o

CFLAGS1 = -DOPENFUN=luaopen_${MODNAME}_core
CFLAGS2 = -DLUA_USE_LINUX

XCFLAGS=-g

CFLAGS=$CFLAGS1 $CFLAGS2 $LUA_CFLAGS

%.o: %.c
	$CC $CFLAGS $XCFLAGS -c -o $target $stem.c

lib:V: $LIBNAME fastmime.so

$OBJS $XOBJS: mkconfig mk.sharedlib

LIBS=$LUA_LFLAGS $LOCKLIBS -lm

$LIBNAME: $OBJS $XOBJS
	$CC $CFLAGS $LIB_OPTION -o $LIBNAME $OBJS $LIBS

fastmime.so: fastmime.o
	$CC $CFLAGS $LIB_OPTION -o fastmime.so fastmime.o

osbf-lua: $OBJS lua.o main.o
	$CC $CFLAGS  -o osbf-lua main.o $OBJS lua.o $LIBDEBUG $PGLUALIB $PG -ldl -lreadline -lhistory -lncurses $LIBS 

mem-test: small.o lua.o main.o
	$CC $CFLAGS  -o mem-test main.o small.o lua.o $LIBDEBUG $PGLUALIB $PG -ldl -lreadline -lhistory -lncurses $LIBS 

install: $LIBNAME fastmime.so
	mkdir -p $LUACMODULE_DIR/$MODNAME
	cp $LIBNAME $LUACMODULE_DIR/$MODNAME/core.so
	cp fastmime.so $LUACMODULE_DIR/fastmime.so
	mkdir -p $LUALMODULE_DIR/$MODNAME
	cp lua/*.lua $LUALMODULE_DIR/$MODNAME
	# cp and rm may work where mv will not (directory permissions)
	cp $LUALMODULE_DIR/$MODNAME/osbf.lua $LUALMODULE_DIR/$MODNAME.lua
	rm $LUALMODULE_DIR/$MODNAME/osbf.lua
	echo "#! $LUABIN" > $BINDIR/$BINNAME
	sed '/^#!/d' lua/osbf |
	  lua -e "x=string.gsub(io.read('*a'),'osbf','$MODNAME') io.write(x)" \
              >> $BINDIR/$BINNAME
	chmod +x $BINDIR/$BINNAME

uninstall: 
	rm -rf $LUALMODULE_DIR/$MODNAME $LUALMODULE_DIR/$MODNAME.lua
	rm -rf $LUACMODULE_DIR/$MODNAME $LUACMODULE_DIR/$MODNAME.lua
	rm -rf $BINDIR/$BINNAME

test: install
	$LUABIN -l$MODNAME -l$MODNAME.command_line ./print-contents $MODNAME
	$LUABIN -l$MODNAME -l$MODNAME.roc < /dev/null
	$LUABIN -l$MODNAME -l$MODNAME.mlearn < /dev/null
	$LUABIN ./test-headers $MODNAME $MAILFILE
	$LUABIN -l$MODNAME -e "m = $MODNAME.cache.msg_of_any '$MAILFILE'; print(m)" -i

clean:
	rm -f $LIBNAME $OBJS *.so *~
	rm -f *.o *.gcda *.gcno


depend: $SRCS $HFILES strip-lua-headers
	gcc $CFLAGS -MM $SRCS | lua strip-lua-headers $LUA_CFLAGS > $target

<depend

mk%: mk%.in config.status
	./config.status $target

mk.sharedlib:Q: config.status
	# if this "autoconf" doesn't work for you, set LIB_OPTION for shared
	# object manually.
	case "`ld -V -o /dev/null 2>&1`" in
           *Solaris*) 
             # Solaris - tested with 2.6, gcc 2.95.3 20010315 and Solaris ld
             echo "LIB_OPTION= -G -dy"
             ;;
           *GNU*) 
             echo "LIB_OPTION= -shared -dy"
             ;;
           *)
             echo "LIB_OPTION= -error -this-compile-must-fail"
             echo "Cannot determined shared library option" 1>&2
             exit 1
             ;;
        esac > $target
	cat $target
