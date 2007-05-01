SRC=$(shell echo *.lua)

all: doc

test: 
	(cd ..; make test)

doc: 
	luadoc -d . *.lua

clean: 
	rm -f *.html
	rm -f dep.dot
	rm -f *.ps

dep.dot: $(SRC) dep-to-dot
	sh dep-to-dot $(SRC) > dep.dot

