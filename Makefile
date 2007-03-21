T= osbf

include ./config

DIST_DIR= osbf-$LIB_VERSION
TAR_FILE= $(DIST_DIR).tar.gz
ZIP_FILE= $(DIST_DIR).zip
LIBNAME= lib$T$(LIB_EXT).$(LIB_VERSION)
MAILFILE = $(shell ./mailfile)

SRCS= losbflib.c osbf_bayes.c osbf_aux.c
OBJS= losbflib.o osbf_bayes.o osbf_aux.o


lib: $(LIBNAME)

*.o:	*.c osbflib.h config

$(LIBNAME): $(OBJS)
	$(CC) $(CFLAGS) $(LIB_OPTION) -o $(LIBNAME) $(OBJS) $(LIBS)

install: $(LIBNAME)
	mkdir -p $(LUAMODULE_DIR)/osbf
	strip $(LIBNAME)
	cp $(LIBNAME) $(LUAMODULE_DIR)/osbf/core$(LIB_EXT)
	cp lua/osbf.lua $(LUAMODULE_DIR)
	cp lua/*.lua $(LUAMODULE_DIR)/osbf
	rm -f $(LUAMODULE_DIR)/osbf/osbf.lua # ugly, but so what

test: install
	lua5.1 -losbf ./print-contents
	lua5.1 -losbf -e "m = osbf.msg.of_file '$(MAILFILE)'" -i

install_spamfilter:
	mkdir -p $(SPAMFILTER_DIR)
	cp spamfilter/* $(SPAMFILTER_DIR)
	chmod 755 $(SPAMFILTER_DIR)/*.lua

clean:
	rm -f $L $(LIBNAME) $(OBJS) *.so *~ spamfilter/*~

