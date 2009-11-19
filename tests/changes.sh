set -ev

mkdir temp
cd temp
iolaus init

date > foo
iolaus record -am addfoo
echo hi there > foo
iolaus record -am hello
date > foo
iolaus record -am datefoo
echo bye there > foo
iolaus record -am bye

# check that changes --count works properly
iolaus changes --count > num
cat num
echo 4 | diff -u num -
rm num

iolaus changes > ch
cat ch
grep bye ch

iolaus changes --reverse > rch
cat rch
grep bye rch

sort rch > srch
sort ch > sch

diff -u srch sch
