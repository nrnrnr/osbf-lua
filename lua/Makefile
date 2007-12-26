SRC=$(shell echo *.lua)

all: test

test: 
	./test-hiding
	(cd ..; make test < /dev/null)

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


################  generated with gcc -MM

osbf_aux.o: osbf_aux.c osbflib.h osbferr.h
osbf_bayes.o: osbf_bayes.c osbflib.h osbferr.h
osbf_csv.o: osbf_csv.c osbflib.h osbferr.h
osbf_disk.o: osbf_disk.c osbflib.h osbferr.h osbf_disk.h
osbf_fmt_5.o: osbf_fmt_5.c osbflib.h osbferr.h osbf_disk.h osbfcvt.h
osbf_fmt_6.o: osbf_fmt_6.c osbflib.h osbferr.h osbf_disk.h
osbf_fmt_ers.o: osbf_fmt_ers.c osbf_disk.h osbflib.h osbferr.h
osbf_native.o: osbf_native.c
osbf_stats.o: osbf_stats.c osbflib.h osbferr.h
osbferrl.o: osbferrl.c osbferr.h
osbferrs.o: osbferrs.c osbferr.h
