
LUA              = @LUA@
MOD_NAME         = @MOD_NAME@
LUA_INSTALL_CMOD = @LUA_INSTALL_CMOD@
#LUA_INSTALL_LMOD = @LUA_INSTALL_LMOD@
#force lua modules to be installed together with C modules
LUA_INSTALL_LMOD = $(LUA_INSTALL_CMOD)

EXTRA_DIST =  boot.lua cache.lua cfg.lua classifier.lua \
              command_line.lua commands.lua core_doc.lua.in \
              default_cfg.lua filter.lua  internals.lua \
              learn.lua lists.lua log.lua mime.lua mlearn.lua \
              msg.lua multitree.lua omsg.lua options.lua \
              output.lua report.lua roc.lua sfid.lua util.lua.in \
              dep-to-dot count-lines dep-to-dot design.dot \
              Makefile.original osbf.in osbf.lua.in README \
              STATUS test-hiding

LUA_MODULES = boot.lua cache.lua cfg.lua classifier.lua \
              command_line.lua commands.lua core_doc.lua \
              default_cfg.lua filter.lua  internals.lua \
              learn.lua lists.lua log.lua mime.lua mlearn.lua \
              msg.lua multitree.lua omsg.lua options.lua \
              output.lua report.lua roc.lua sfid.lua util.lua

CLEANFILES = *.html dep.dot *.ps

osbfmoduledir = $(LUA_INSTALL_LMOD)
osbfmodule_DATA = $(MOD_NAME).lua

auxmodulesdir = $(LUA_INSTALL_LMOD)/$(MOD_NAME)
auxmodules_DATA = $(LUA_MODULES)

osbfbindir = $(prefix)/bin
osbfbin_SCRIPTS = $(MOD_NAME)
EXTRA_SCRIPTS=


test: 
	./test-hiding
	(cd ..; make test < /dev/null)

doc: 
	luadoc -d . *.lua

dep.dot: $(LUA_MODULES) dep-to-dot
	sh dep-to-dot $(LUA_MODULES) > dep.dot

dep.ps: dep.dot
	dot -Tps dep.dot > dep.ps

count:
	./count-lines -except learn2 multitree omsg $(MOD_NAME) -- *.lua osbf

