MODNAME=osbf3

include ./config

DIST_DIR= osbf-$LIB_VERSION
TAR_FILE= $(DIST_DIR).tar.gz
ZIP_FILE= $(DIST_DIR).zip
LIBNAME= lib$(MODNAME)$(LIB_EXT).$(LIB_VERSION)
BINNAME=osbf3


MAILFILE = $(shell ./mailfile)

SRCS= losbflib.c osbf_bayes.c osbf_aux.c osbf_disk.c
OBJS= losbflib.o osbf_bayes.o osbf_aux.o osbf_disk.o

CFLAGS += -DOPENFUN=luaopen_$(MODNAME)_core
CFLAGS += -DLUA_USE_LINUX

lib: $(LIBNAME)

losbflib.o: losbflib.c osbflib.h config
osbf_aux.o: osbf_aux.c osbflib.h config
osbf_bayes.o: osbf_bayes.c osbflib.h config
osbf_disk.o: osbf_disk.c osbflib.h config

$(LIBNAME): $(OBJS)
	$(CC) $(CFLAGS) $(LIB_OPTION) -o $(LIBNAME) $(OBJS) $(LIBS)

osbf-lua: $(OBJS) lua.o main.o
	$(CC) $(CFLAGS) -o osbf-lua main.o $(OBJS) lua.o -L$(PGDIR)/lib -llua -ldl -lreadline -lhistory -lncurses $(LIBS) 

install: $(LIBNAME)
	mkdir -p $(LUAMODULE_DIR)/$(MODNAME)
	cp $(LIBNAME) $(LUAMODULE_DIR)/$(MODNAME)/core$(LIB_EXT)
ifneq ($(STRIP),no)
	strip $(LUAMODULE_DIR)/$(MODNAME)/core$(LIB_EXT)
endif
	cp lua/*.lua $(LUAMODULE_DIR)/$(MODNAME)
	mv $(LUAMODULE_DIR)/$(MODNAME)/osbf.lua $(LUAMODULE_DIR)/$(MODNAME).lua
	echo "#! $(LUABIN)" > $(BINDIR)/$(BINNAME)
	lua -e "x=string.gsub(io.read('*a'),'osbf','$(MODNAME)') io.write(x)" < lua/osbf >> $(BINDIR)/$(BINNAME)
	chmod +x $(BINDIR)/$(BINNAME)

uninstall: 
	rm -rf $(LUAMODULE_DIR)/$(MODNAME) $(LUAMODULE_DIR)/$(MODNAME).lua
	rm -rf $(BINDIR)/$(BINNAME)

test: install
	$(LUABIN) -l$(MODNAME) ./print-contents $(MODNAME)
	$(LUABIN) ./test-headers $(MODNAME) $(MAILFILE)
	$(LUABIN) -l$(MODNAME) -e "m = $(MODNAME).msg.of_file '$(MAILFILE)'" -i

clean:
	rm -f $(LIBNAME) $(OBJS) *.so *~

