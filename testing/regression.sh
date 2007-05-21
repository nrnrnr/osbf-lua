#! /bin/sh

dir=`dirname $0`
cd $dir

TREC=trec06p_full

case $1 in
  -trec) TREC="$2" ; shift ; shift ;;
esac

# sets udir to /tmp/osbf-lua
if [ ! -x trec.lua ]; then
  echo 'trec.lua not found in testing dir ' 1>&2; exit 1
fi

if [ ! -r $TREC/index ]; then
  echo "$TREC does not seem to point to a TREC index" 1>&2; exit 1
fi

./trec.lua "$TREC" > result

/bin/rm -f *.md5
md5sum result > result.md5
md5sum /tmp/osbf-lua/*.cfc | sort > databases.md5
md5sum /tmp/osbf-lua/cache/* | sort |
  sed -e 's/\(sfid-.\)[0-9]*-[0-9]*/\1/' -e 's/-.@/@/' > cache.md5
> regression.txt
for f in *.md5; do
  diff -u $f ${f}.ok >> regression.txt
done
r=`head -1 regression.txt`
if [ "$r" != "" ]; then
  more regression.txt
else
  echo Regression OK
fi

