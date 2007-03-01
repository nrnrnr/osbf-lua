
all: osbf.html

test: 
	(cd ..; make test)


.SUFFIXES: .lua .html

.lua.html:
	luadoc -d . $*.lua > $*.html