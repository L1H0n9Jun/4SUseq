#!/bin/bash
scriptsdir=$(readlink -f $(dirname "$0"))

for f in `ls *R1*.fastq.gz`; do
y=`zcat $f|head -n1|awk '{print(substr($1,1,4))}'`
echo "zcat $f|grep \"^$y\"|awk -F\":\" '{print \$3,\$4}'|sort|uniq -c > ${f}.lanes.txt"
zcat $f|grep "^$y" | awk -F ":" '{print $3,$4}'|sort|uniq -c > ${f}.lanes.txt
done
# jobid=`swarm -f do_lanes --partition=ccr,norm`
#jobid=`swarm -f do_lanes --partition=quick`
#sleep 15
#while true;do
#if [ `squeue -j $jobid|wc -l` -eq 1 ]; then
#break
#else
#sleep 30
#fi
#done
for f in `ls *R1*.fastq.gz.lanes.txt`;do
    bn=$(basename $f)
    awk -v f=${bn%.R1.*} -v OFS="\t" '{print f,$0}' $f;
done | sort -k1,1 -k4,4n > lanes.txt

rm -f *gz.lanes.txt
#rm -f do_lanes

cat lanes.txt | /home/kwang34/miniconda3/envs/snakemake/bin/python ${scriptsdir}/collapse_lanes.py |awk -v OFS="\t" '{print "#",$_}' >> lanes.txt
grep -v "^#" lanes.txt|awk '{print $3}'|sort|uniq -c |awk -v OFS="\t" '{print "##",$1,$2}' >> lanes.txt
