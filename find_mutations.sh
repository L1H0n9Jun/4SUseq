#!/usr/bin/env bash
# Author: Vishal Koparde, Ph.D.
# CCBR, NCI
# (c) 2021
#
#
# find_mutations
# this workflow tries to
# 1. Align readpairs to genome using HiSAT2 
# 2. find T-to-C mutations in readpairs mapping to the + strand 
# 3. find A-to-G mutations in readpairs mapping to the - strand
set -euo pipefail
module purge

function get_git_commitid_tag() {
  cd $1
  gid=$(git rev-parse HEAD)
  tag=$(git describe --tags $gid)
  echo -ne "$gid\t$tag"
}

# ## setting PIPELINE_HOME
# ## clone the pipeline to a folder
# ## git clone https://github.com/RBL-NCI/4SUseq.git
# ## and set that as the pipeline home
# PIPELINE_HOME="/data/RBL_NCI/Wolin/mESC_slam_analysis/workflow/4SUseq"
PIPELINE_HOME=$(readlink -f $(dirname "$0"))
echo "Pipeline Dir: $PIPELINE_HOME"
# hg38 and mm10 hisat2 prebuilt indices
HISAT2INDEXDIR="/data/RBL_NCI/Wolin/mESC_slam_analysis/resources"
# other smaller resources are in resourcesdir from config.yaml
# ## make current folder as working directory
# a=$(readlink -f $0)
# # echo $a
# for i in `seq 1 20`;do
# b=$(echo $a|sed "s/\/gpfs\/gsfs${i}\/users/\/data/g")
# a=$b
# done
# # echo $a
# WORKDIR=$(dirname $a)
GIT_COMMIT_TAG=$(get_git_commitid_tag $PIPELINE_HOME)
echo "Git Commit/Tag: $GIT_COMMIT_TAG"

function usage() { cat << EOF
find_mutations.sh: find T-to-C mutations
USAGE:
  bash find_mutations.sh <MODE> <path_to_workdir>
Required Positional Argument:
  MODE: [Type: Str] Valid options:
    a) init <path_to_workdir> : initialize workdir
    b) run <path_to_workdir>: run with slurm
    c) reset <path_to_workdir> : DELETE workdir dir and re-init it
    e) dryrun <path_to_workdir> : dry run snakemake to generate DAG
    f) unlock <path_to_workdir> : unlock workdir if locked by snakemake
    g) runlocal <path_to_workdir>: run without submitting to sbatch
EOF
}

function err() { cat <<< "
#
#
#
  $@
#
#
#
" 1>&2; }

function runcheck(){
  if [ "$#" -eq "1" ]; then err "absolute path to the working dir needed"; usage; exit 1; fi
  if [ "$#" -gt "2" ]; then err "too many arguments"; usage; exit 1; fi
  WORKDIR=$2
  echo "Working Dir: $WORKDIR"
  if [ ! -d $WORKDIR ];then err "Folder $WORKDIR does not exist!"; exit 1; fi
  module load python/3.7
  module load snakemake/5.24.1
}

function dryrun() {
  runcheck "$@"
  run "--dry-run"
}

function unlock() {
  runcheck "$@"
  run "--unlock"  
}

function init() {
if [ "$#" -eq "1" ]; then err "init needs an absolute path to the working dir"; usage; exit 1; fi
if [ "$#" -gt "2" ]; then err "init takes only one more argument"; usage; exit 1;fi
WORKDIR=$2
x=$(echo $WORKDIR|awk '{print substr($1,1,1)}')
if [ "$x" != "/" ]; then err "working dir should be supplied as an absolute path"; usage; exit 1; fi
echo "Working Dir: $WORKDIR"
if [ -d $WORKDIR ];then err "Folder $WORKDIR already exists!"; exit 1; fi
mkdir -p $WORKDIR
# copy config.yaml and samples.tsv template files into the working dir
echo ${PIPELINE_HOME}
echo ${WORKDIR}
sed -e "s/PIPELINE_HOME/${PIPELINE_HOME//\//\\/}/g" -e "s/WORKDIR/${WORKDIR//\//\\/}/g" -e "s/HISAT2INDEXDIR/${HISAT2INDEXDIR//\//\\/}/g" ${PIPELINE_HOME}/config/config.yaml > $WORKDIR/config.yaml
sed -e "s/PIPELINE_HOME/${PIPELINE_HOME//\//\\/}/g" -e "s/WORKDIR/${WORKDIR//\//\\/}/g" ${PIPELINE_HOME}/config/samples_test.tsv > $WORKDIR/samples.tsv

# cp ${PIPELINE_HOME}/config/samples.tsv $WORKDIR/

#create log and stats folders
if [ ! -d $WORKDIR/logs ]; then mkdir -p $WORKDIR/logs;echo "Logs Dir: $WORKDIR/logs";fi
if [ ! -d $WORKDIR/stats ];then mkdir -p $WORKDIR/stats;echo "Stats Dir: $WORKDIR/stats";fi

echo "Done Initializing $WORKDIR. You can now edit $WORKDIR/config.yaml and $WORKDIR/samples.tsv"

}

function runlocal() {
  runcheck "$@"
  if [ "$SLURM_JOB_ID" == "" ];then err "runlocal can only be done on an interactive node"; exit 1; fi
  module load singularity
  run "local"
}

function runslurm() {
  runcheck "$@"
  run "slurm"
}

function run () {
  echo "Running..."
  ## check if initialized
  for f in config.yaml samples.tsv; do
    if [ ! -f $WORKDIR/$f ]; then err "Error: '${f}' file not found in workdir ... initialize first!";usage && exit 1;fi
  done

  ## Archive previous run files
  if [ -f ${WORKDIR}/snakemake.log ];then 
    modtime=$(stat ${WORKDIR}/snakemake.log |grep Modify|awk '{print $2,$3}'|awk -F"." '{print $1}'|sed "s/ //g"|sed "s/-//g"|sed "s/://g")
    mv ${WORKDIR}/snakemake.log ${WORKDIR}/stats/snakemake.${modtime}.log
  fi
  if [ -f ${WORKDIR}/snakemake.stats ];then 
    modtime=$(stat ${WORKDIR}/snakemake.stats |grep Modify|awk '{print $2,$3}'|awk -F"." '{print $1}'|sed "s/ //g"|sed "s/-//g"|sed "s/://g")
    mv ${WORKDIR}/snakemake.stats ${WORKDIR}/stats/snakemake.${modtime}.stats
  fi
  nslurmouts=$(find ${WORKDIR} -maxdepth 1 -name "slurm-*.out" |wc -l)
  if [ "$nslurmouts" != "0" ];then
    for f in $(ls ${WORKDIR}/slurm-*.out);do gzip -n $f;mv ${f}.gz ${WORKDIR}/logs/;done
  fi

  ## Archive previous run files
  if [ -f ${WORKDIR}/snakemake.log ];then 
    modtime=$(stat ${WORKDIR}/snakemake.log |grep Modify|awk '{print $2,$3}'|awk -F"." '{print $1}'|sed "s/ //g"|sed "s/-//g"|sed "s/://g")
    mv ${WORKDIR}/snakemake.log ${WORKDIR}/stats/snakemake.log.${modtime} && gzip -n ${WORKDIR}/stats/snakemake.log.${modtime}
  fi
  if [ -f ${WORKDIR}/snakemake.stats ];then 
    modtime=$(stat ${WORKDIR}/snakemake.stats |grep Modify|awk '{print $2,$3}'|awk -F"." '{print $1}'|sed "s/ //g"|sed "s/-//g"|sed "s/://g")
    mv ${WORKDIR}/snakemake.stats ${WORKDIR}/stats/snakemake.stats.${modtime} && gzip -n ${WORKDIR}/stats/snakemake.stats.${modtime}
  fi

  cd $WORKDIR

  SNAKEFILE="${PIPELINE_HOME}/workflow/find_mutations.snakefile"

  if [ "$1" == "local" ];then

  snakemake -s $SNAKEFILE \
  --directory $WORKDIR \
  --use-envmodules \
  --printshellcmds \
  --latency-wait 120 \
  --configfile $WORKDIR/config.yaml \
  --cores all \
  --stats ${WORKDIR}/snakemake.stats \
  2>&1|tee ${WORKDIR}/snakemake.log

  if [ "$?" -eq "0" ];then
    snakemake -s $SNAKEFILE \
    --report ${WORKDIR}/find_mutations.runlocal_snakemake_report.html \
    --directory $WORKDIR \
    --configfile ${WORKDIR}/config.yaml 
  fi

  elif [ "$1" == "slurm" ];then

  cat > ${WORKDIR}/submit_find_mutations_script.sbatch << EOF
#!/bin/bash
#SBATCH --job-name="findmutations"
#SBATCH --mem=10g
#SBATCH --partition="ccr,norm"
#SBATCH --time=96:00:00
#SBATCH --cpus-per-task=2

module load python/3.7
module load snakemake/5.24.1
module load singularity

cd \$SLURM_SUBMIT_DIR

  snakemake -s $SNAKEFILE \
  --directory $WORKDIR \
  --use-envmodules \
  --printshellcmds \
  --latency-wait 120 \
  --restart-times 2 \
  --configfile $WORKDIR/config.yaml \
  --cluster-config ${PIPELINE_HOME}/config/cluster.json \
  --cluster "sbatch --gres {cluster.gres} --cpus-per-task {cluster.threads} -p {cluster.partition} -t {cluster.time} --mem {cluster.mem} --job-name {cluster.name} --output {cluster.output} --error {cluster.error}" \
  -j 500 \
  --rerun-incomplete \
  --keep-going \
  --stats ${WORKDIR}/snakemake.stats \
  2>&1|tee ${WORKDIR}/snakemake.log

  if [ "\$?" -eq "0" ];then
  snakemake -s $SNAKEFILE \
  --directory $WORKDIR \
  --report ${WORKDIR}/find_mutations.runslurm_snakemake_report.html \
  --configfile ${WORKDIR}/config.yaml 

  fi

EOF
sbatch ${WORKDIR}/submit_find_mutations_script.sbatch

  else

snakemake $1 -s $SNAKEFILE \
--directory $WORKDIR \
--use-envmodules \
--printshellcmds \
--latency-wait 120 \
--configfile ${WORKDIR}/config.yaml \
--cluster-config ${PIPELINE_HOME}/config/cluster.json \
--cluster "sbatch --gres {cluster.gres} --cpus-per-task {cluster.threads} -p {cluster.partition} -t {cluster.time} --mem {cluster.mem} --job-name {cluster.name} --output {cluster.output} --error {cluster.error}" \
-j 500 \
--rerun-incomplete \
--keep-going \
--stats ${WORKDIR}/snakemake.stats

  fi

}

function reset() {
if [ "$#" -eq "1" ]; then err "cleanup needs an absolute path to the existing working dir"; usage; fi
if [ "$#" -gt "2" ]; then err "cleanup takes only one more argument"; usage; fi
WORKDIR=$2
echo "Working Dir: $WORKDIR"
if [ ! -d $WORKDIR ];then err "Folder $WORKDIR does not exist!";fi
echo "Deleting $WORKDIR"
rm -rf $WORKDIR
echo "Re-Initializing $WORKDIR"
init "$@"
}



function main(){

  if [ $# -eq 0 ]; then usage; exit 1; fi

  case $1 in
    init) init "$@" && exit 0;;
    dryrun) dryrun "$@" && exit 0;;
    unlock) unlock "$@" && exit 0;;
    run) runslurm "$@" && exit 0;;
    runlocal) runlocal "$@" && exit 0;;
    reset) reset "$@" && exit 0;;
    -h | --help | help) usage && exit 0;;
    -* | --*) err "Error: Failed to provide mode: <init|run>."; usage && exit 1;;
    *) err "Error: Failed to provide mode: <init|run>. '${1}' is not supported."; usage && exit 1;;
  esac
}

main "$@"
