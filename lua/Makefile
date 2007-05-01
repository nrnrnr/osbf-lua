SRC=$(shell echo *.lua)

all: doc

test: 
	(cd ..; make test)

install: 
	(cd ..; make install)

doc: 
	luadoc -d . *.lua

clean: 
	rm -f *.html
	rm -f dep.dot
	rm -f *.ps

dep.dot: $(SRC) dep-to-dot
	sh dep-to-dot $(SRC) > dep.dot

dep.ps: dep.dot
	dot -Tps dep.dot > dep.ps
