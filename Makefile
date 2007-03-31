MODNAME=osbf3

include ./config

DIST_DIR= osbf-$LIB_VERSION
TAR_FILE= $(DIST_DIR).tar.gz
ZIP_FILE= $(DIST_DIR).zip
LIBNAME= lib$T$(LIB_EXT).$(LIB_VERSION)
BINNAME=osbf3


MAILFILE = $(shell ./mailfile)

SRCS= losbflib.c osbf_bayes.c osbf_aux.c
OBJS= losbflib.o osbf_bayes.o osbf_aux.o

CFLAGS += -DOPENFUN=luaopen_$(MODNAME)_core

lib: $(LIBNAME)

*.o:	*.c osbflib.h config

$(LIBNAME): $(OBJS)
	$(CC) $(CFLAGS) $(LIB_OPTION) -o $(LIBNAME) $(OBJS) $(LIBS)

install: $(LIBNAME)
	mkdir -p $(LUAMODULE_DIR)/$(MODNAME)
	strip $(LIBNAME)
	cp $(LIBNAME) $(LUAMODULE_DIR)/$(MODNAME)/core$(LIB_EXT)
	cp lua/osbf.lua $(LUAMODULE_DIR)/$(MODNAME).lua
	cp lua/*.lua $(LUAMODULE_DIR)/$(MODNAME)
	rm -f $(LUAMODULE_DIR)/$(MODNAME)/osbf.lua # ugly, but so what
	sed "s/osbf/$(MODNAME)/g" lua/osbf > $(BINDIR)/$(BINNAME)
	chmod +x $(BINDIR)/$(BINNAME)

uninstall: 
	rm -rf $(LUAMODULE_DIR)/osbf $(LUAMODULE_DIR)/osbf.lua
	rm -rf $(BINDIR)/$(BINNAME)

test: install
	lua5.1 -l$(MODNAME) ./print-contents $(MODNAME)
	lua5.1 -l$(MODNAME) -e "m = $(MODNAME).msg.of_file '$(MAILFILE)'" -i

install_spamfilter:
	mkdir -p $(SPAMFILTER_DIR)
	cp spamfilter/* $(SPAMFILTER_DIR)
	chmod 755 $(SPAMFILTER_DIR)/*.lua

clean:
	rm -f $L $(LIBNAME) $(OBJS) *.so *~ spamfilter/*~

