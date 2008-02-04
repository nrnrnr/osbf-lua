MODNAME=osbf3

include ./config

DIST_DIR= osbf-$LIB_VERSION
TAR_FILE= $(DIST_DIR).tar.gz
ZIP_FILE= $(DIST_DIR).zip
LIBNAME= lib$(MODNAME)$(LIB_EXT).$(LIB_VERSION)
BINNAME=osbf3


MAILFILE = $(shell ./mailfile)

HFILES= oarray.h osbf_disk.h osbfcvt.h osbferr.h osbflib.h
SRCS= losbflib.c osbferrl.c oarray.c \
      osbf_bayes.c osbf_aux.c osbf_disk.c osbf_csv.c osbf_stats.c \
      osbf_fmt_5.c osbf_fmt_6.c osbf_fmt_7.c 
OBJS= losbflib.o osbferrl.o oarray.o \
      osbf_bayes.o osbf_aux.o osbf_disk.o osbf_csv.o osbf_stats.o \
      osbf_fmt_5.o osbf_fmt_6.o osbf_fmt_7.o
XOBJS= osbferrs.o

CFLAGS += -DOPENFUN=luaopen_$(MODNAME)_core
CFLAGS += -DLUA_USE_LINUX

lib: $(LIBNAME)

$(OBJS) $(XOBJS): osbflib.h osbferr.h config pgconfig

osbferrs.o: osbferr.h
osbf_disk.o: osbf_disk.h
oarray.o: osbferr.h oarray.h

$(LIBNAME): $(OBJS) $(XOBJS)
	$(CC) $(CFLAGS) $(LIB_OPTION) -o $(LIBNAME) $(OBJS) $(LIBS)

osbf-lua: $(OBJS) lua.o main.o
	$(CC) $(CFLAGS)  -o osbf-lua main.o $(OBJS) lua.o $(LIBDEBUG) $(PGLUALIB) $(PG) -ldl -lreadline -lhistory -lncurses $(LIBS) 

mem-test: small.o lua.o main.o
	$(CC) $(CFLAGS)  -o mem-test main.o small.o lua.o $(LIBDEBUG) $(PGLUALIB) $(PG) -ldl -lreadline -lhistory -lncurses $(LIBS) 

lua.o: config
main.o: config

install: $(LIBNAME)
	mkdir -p $(LUAMODULE_DIR)/$(MODNAME)
	cp $(LIBNAME) $(LUAMODULE_DIR)/$(MODNAME)/core$(LIB_EXT)
ifneq ($(STRIP),no)
	strip $(LUAMODULE_DIR)/$(MODNAME)/core$(LIB_EXT)
endif
	cp lua/*.lua $(LUAMODULE_DIR)/$(MODNAME)
	# cp and rm may work where mv will not (directory permissions)
	cp $(LUAMODULE_DIR)/$(MODNAME)/osbf.lua $(LUAMODULE_DIR)/$(MODNAME).lua
	rm $(LUAMODULE_DIR)/$(MODNAME)/osbf.lua
	echo "#! $(LUABIN)" > $(BINDIR)/$(BINNAME)
	lua -e "x=string.gsub(io.read('*a'),'osbf','$(MODNAME)') io.write(x)" < lua/osbf >> $(BINDIR)/$(BINNAME)
	chmod +x $(BINDIR)/$(BINNAME)

uninstall: 
	rm -rf $(LUAMODULE_DIR)/$(MODNAME) $(LUAMODULE_DIR)/$(MODNAME).lua
	rm -rf $(BINDIR)/$(BINNAME)

test: install
	$(LUABIN) -l$(MODNAME) ./print-contents $(MODNAME)
	$(LUABIN) -l$(MODNAME) -l$(MODNAME).roc < /dev/null
	$(LUABIN) ./test-headers $(MODNAME) $(MAILFILE)
	$(LUABIN) -l$(MODNAME) -e "m = $(MODNAME).msg.of_file '$(MAILFILE)'" -i

clean:
	rm -f $(LIBNAME) $(OBJS) *.so *~
	rm -f *.o *.gcda *.gcno


depend: $(SRCS) $(HFILES) strip-lua-headers
	gcc $(CFLAGS) -MM $(SRCS) | ./strip-lua-headers `pkg-config --cflags lua5.1` > $@

include ./depend

