#!/bin/csh

cd ./test

date

set lbdirect = 50
set sione = 2048
set sitwo = 128
set sithree = 128
set sifour = 128

#=========================================================================================

if     ($1 == "fid")       goto FID
if     ($1 == "ft1phase")  goto FT1PHASE
if     ($1 == "ft1")       goto FT1
if     ($1 == "ist")       goto IST
if     ($1 == "ist1")      goto IST1
if     ($1 == "pipe")      goto PH2PIPE
if     ($1 == "projphase") goto PROJPHASE 
if     ($1 == "ft2phase")  goto FT2PHASE
if     ($1 == "ft3phase")  goto FT3PHASE
if     ($1 == "ft4phase")  goto FT4PHASE
if     ($1 == "ftall")     goto FTALL
if     ($1 == "ccpnmr")    goto CCPNMR
if     ($1 == "clean")     goto CLEAN
goto DONE

#=========================================================================================

FID:

rm -rf fid
mkdir fid

echo " Loading bruker FID starts here"

bruk2pipe -in ./ser \
  -bad 0.0 -ext -aswap -DMX -decim 960 -dspfvs 20 -grpdly 68  \
  -xN              2048  -yN               8   -zN               435  -aN               0 \
  -xT               1024   -yT                8    -zT                435  -aT                0  \
  -xMODE            DQD  -yMODE         Real   -zMODE           Real  -aMODE       Complex  \
  -xSW        20833.333  -ySW         2631.579  -zSW        3846.154  -aSW         1999.995  \
  -xOBS         700.404  -yOBS          70.979  -zOBS        176.146  -aOBS         176.146  \
  -xCAR           5.087  -yCAR         119.004  -zCAR        175.977  -aCAR         175.977  \
  -xLAB              HN  -yLAB              N   -zLAB             CA  -aLAB              CO  \
  -ndim               3  -aq2D         States                         \
  -out ./fid/test_%04d.fid -verb -ov

echo " Loading bruker FID ends here"
goto FT1

#=========================================================================================

FT1PHASE: 

rm -fr ft1
mkdir ft1
echo "check FT1 for phasing starts here"

xyz2pipe -in ./fid/test_%04d.fid -x                       \
| nmrPipe  -fn ZF -size $sione                          \
| nmrPipe  -fn EM -lb $lbdirect -c 0.5                      \
#| nmrPipe  -fn GM -g1 -20.0 -g3 0.01                      \
#| nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 2 -c 0.5    \
| nmrPipe  -fn FT   -auto -verb                         \
| nmrPipe  -fn PS -p0 235 -p1 0 -di             \
#| nmrPipe  -fn POLY -auto -ord 4 -x1 100ppm -xn -100ppm   \
| nmrPipe  -fn EXT -x1 11ppm -xn 6ppm -sw -round 2      \
| pipe2xyz -ov -out ./ft1/test_%04d.ft -x


echo "check FT1 for phasing ends here"
goto DONE

#=========================================================================================

FT1: 

# This file is for preparing the 3D files for NUS construction  
# format of output file should be "phase increments time increments direct dimension". 
# This is achieved by the following file. 
# Till now we are treating the experiment file as 3D
# Get proper phase values from "ft1phasing.com" program 


rm -fr ft1
mkdir ft1
echo "Prepare FT1 for NUS starts here"

xyz2pipe -in fid/test_%04d.fid -x                       \
| nmrPipe  -fn ZF -size $sione                          \
| nmrPipe  -fn EM -lb $lbdirect -c 0.5                      \
| nmrPipe  -fn FT   -auto -verb                         \
| nmrPipe  -fn PS -p0 235 -p1 0 -di             \
| nmrPipe  -fn EXT -x1 11ppm -xn 6ppm -sw -round 2      \
| nmrPipe  -fn ZTP -verb                                \
| pipe2xyz -ov -out ft1/test_%04d.ft -y

echo "Prepare FT1 for NUS ends here"
goto IST1

#=========================================================================================

IST:

rm -fr ft1_ist
mkdir ft1_ist

pwd 

./../parallel -j 100% './runist_cluster4D_600 {} > /dev/null; echo {}' ::: ./ft1/test*.ft

echo "IST prediction is finished"

goto DONE

#=========================================================================================

IST1:

date

# change number of iterations accordingly
# check "schedule" file and numbers are correct

echo 'Reconstruction starts here'

rm -fr ft1_ist
mkdir ft1_ist

foreach F (ft1/*)

set in = $F:t
set out = $F:t:r.phf


./../istHMS -dim 3 -ref 0 -user 1 -incr 1 -xN 27 -yN 23 -zN 14  \
    -itr 250 -verb 1 -sched ./nuslist  \
    < ./ft1/${in} >! ./ft1_ist/${out}

end

echo "IST prediction is finished"

goto PH2PIPE

#=========================================================================================

PH2PIPE:

rm -rf ft1_pipe
mkdir ft1_pipe

xyz2pipe -in ft1_ist/test_%04d.phf | ./../phf2pipe -user 1 -xproj xa.ft1 -yproj ya.ft1 -zproj za.ft1 \
| pipe2xyz -out ft1_pipe/test%03d%03d.ft -ov 

echo "Phf2pipe is finished"

goto FTALL

#=========================================================================================

PROJPHASE:


if ($2 == "first")  goto FIRST
if ($2 == "second") goto SECOND
if ($2 == "third")  goto THIRD

FIRST: 

rm -rf xa.ft2
echo "Projection phasing in the first indirect dimension started "

nmrPipe -in xa.ft1\
 | nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 2 -c 0.5  \
 | nmrPipe  -fn ZF -size 1024                          \
 | nmrPipe  -fn FT -alt  -verb                      \
 | nmrPipe  -fn PS -p0 0 -p1 0 -di                  \
 -ov -out xa.ft2
 
echo "Projection phasing in the first indirect dimension finished " 

#goto DONE


SECOND: 

rm -rf ya.ft2

echo "Projection phasing in the second indirect dimension started "

nmrPipe -in ya.ft1\
 | nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 2 -c 0.5 \
 | nmrPipe  -fn ZF -size 1024                       \
 | nmrPipe  -fn FT -alt  -verb                      \
 | nmrPipe  -fn PS -p0 0 -p1 0 -di                  \
 -ov -out ya.ft2
 
echo "Projection phasing in the second indirect dimension finished " 

#goto DONE

THIRD: 

rm -rf za.ft2

echo "Projection phasing in the third indirect dimension started "

nmrPipe -in za.ft1\
# | nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 2 -c 0.5  \
 | nmrPipe  -fn EM -lb 100                            \
 | nmrPipe  -fn ZF -size 1024                          \
 | nmrPipe  -fn FT -alt  -verb                      \
 | nmrPipe  -fn PS -p0 0 -p1 0 -di                  \
 -ov -out za.ft2
 
echo "Projection phasing in the third indirect dimension finished " 

goto DONE

#=========================================================================================

FT2PHASE: 

rm -rf ft2
rm -rf ft21

mkdir  ft2
mkdir  ft21

echo " Phasing in the first indirect dimension starts here"
echo "FT -alt option is for correcting spectrum that symmetric about mirror"

xyz2pipe -in ft1_pipe/test%03d%03d.ft -x -verb          \
 | nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 1 -c 0.5  \
#| nmrPipe  -fn EM -lb 20                            \
 | nmrPipe  -fn ZF -size 64                         \
 | nmrPipe  -fn FT -alt -verb                       \
| nmrPipe  -fn PS -p0 -0 -p1 0 -di                  \
| pipe2xyz -x -ov -out ft2/test%03d%03d.ft
 
echo " Phasing in the first indirect dimension is done"

xyz2pipe -in ft2/test%03d%03d.ft -a -verb            \
 | nmrPipe  -fn TP                                    \
 | pipe2xyz -x -ov -out ft21/test%03d%03d.ft


echo "check FT2 for phasing ends here"
goto DONE

#=========================================================================================

FT3PHASE: 

rm -rf ft2
rm -rf ft21

mkdir  ft2
mkdir  ft21

echo " Phasing in the second indirect dimension starts here"
echo "FT -alt option is for correcting spectrum that symmetric about mirror"

xyz2pipe -in ft1_pipe/test%03d%03d.ft -y -verb          \
 | nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 1 -c 0.5  \
#| nmrPipe  -fn EM -lb 20                            \
 | nmrPipe  -fn ZF -size 64                         \
 | nmrPipe  -fn FT -alt -verb                            \
 | nmrPipe  -fn PS -p0 -0 -p1 0 -di                  \
 | pipe2xyz -x -ov -out ft2/test%03d%03d.ft
 
echo " Phasing in the second indirect dimension is done"

xyz2pipe -in ft2/test%03d%03d.ft -a -verb            \
 | nmrPipe  -fn TP                                    \
 | pipe2xyz -x -ov -out ft21/test%03d%03d.ft


echo "check FT3 for phasing ends here"
goto DONE

#=========================================================================================

FT4PHASE: 

rm -rf ft2
rm -rf ft21

mkdir  ft2
mkdir  ft21

echo " Phasing in the third indirect dimension starts here"
echo "FT -alt option is for correcting spectrum that symmetric about mirror"

xyz2pipe -in ft1_pipe/test%03d%03d.ft -z -verb          \
# | nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 1 -c 0.5  \
| nmrPipe  -fn EM -lb 50                            \
 | nmrPipe  -fn ZF -size 64                         \
 | nmrPipe  -fn FT -alt -verb                            \
 | nmrPipe  -fn PS -p0 -0 -p1 0 -di                  \
 | pipe2xyz -x -ov -out ft2/test%03d%03d.ft
 
echo " Phasing in the third indirect dimension is done"

xyz2pipe -in ft2/test%03d%03d.ft -a -verb            \
 | nmrPipe  -fn TP                                    \
 | pipe2xyz -x -ov -out ft21/test%03d%03d.ft


echo "check FT4 for phasing ends here"
goto DONE

#=========================================================================================

FTALL:

date

rm -fr ft
mkdir ft
pwd
echo "FT in all indirect dimensions starts here"

xyz2pipe -in ./ft1_pipe/test%03d%03d.ft -x                \
#xyz2pipe -in ft1_pipe/test%04d.ft -x                \
| nmrPipe  -fn ZF -size $sitwo                         \
| nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 2 -c 0.5  \
| nmrPipe  -fn FT  -alt  -verb                      \
| nmrPipe  -fn PS -p0 -0 -p1 0 -di                 \
| nmrPipe  -fn TP                                 \
| nmrPipe  -fn ZF -size $sithree                         \
| nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 2 -c 0.5  \
| nmrPipe  -fn FT -alt -verb                             \
| nmrPipe  -fn PS -p0 0 -p1 0 -di                     \
| pipe2xyz -out ft/test%03d%03d.ft3 -y

xyz2pipe -in ft/test%03d%03d.ft3 -z                       \
| nmrPipe  -fn ZF -size $sithree                       \
#| nmrPipe  -fn EM -lb 50                            \
| nmrPipe  -fn SP -off 0.5 -end 0.98 -pow 2 -c 0.5  \
| nmrPipe  -fn FT -alt -verb                       \
| nmrPipe  -fn PS -p0 0 -p1 0 -di                  \
| pipe2xyz -out ft/test%03d%03d.ft4 -z

date

rm -fr *dat
echo "-skylin for skyline projection"
echo "-sum for sum projection"
echo "-abs for absolution projection"
proj4D.tcl -in ft/test%03d%03d.ft4 -skyline

date

#goto DONE

#=========================================================================================

CCPNMR:
xyz2pipe -in ft/test%03d%03d.ft4 -x > hcocanh4d.ft
#./../pipe2ucsf hcocanh4d.ft hncocanh4d.ucsf
#rm -rf hncocanh4d.ft 
goto DONE


#=========================================================================================

CLEAN:

rm -rf fid
rm -rf ft2
rm -rf ft21
rm -rf ft
rm -rf ft1_ist
rm -rf ft
rm -rf ft1
goto DONE

#=========================================================================================
DONE: 
echo "Finished"

#=========================================================================================
