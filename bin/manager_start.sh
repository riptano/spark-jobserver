#!/bin/bash
# Script to start the job manager
# args: <master> <deployMode> <akkaAdress> <actorName> <workDir> [<proxyUser>]
set -e

get_abs_script_path() {
   pushd . >/dev/null
   cd $(dirname $0)
   appdir=$(pwd)
   popd  >/dev/null
}
get_abs_script_path

. $appdir/setenv.sh

# Override logging options to provide per-context logging
LOGGING_OPTS="$LOGGING_OPTS_FILE
              -DLOG_DIR=$5"

GC_OPTS="-XX:+UseConcMarkSweepGC
         -verbose:gc -XX:+PrintGCTimeStamps
         -XX:MaxPermSize=512m
         -XX:+CMSClassUnloadingEnabled "

JAVA_OPTS="-XX:MaxDirectMemorySize=$MAX_DIRECT_MEMORY
           -XX:+HeapDumpOnOutOfMemoryError -Djava.net.preferIPv4Stack=true"

MAIN="spark.jobserver.JobManager"

# copy files via spark-submit and read them from current (container) dir
if [ $2 = "cluster" -a -z "$REMOTE_JOBSERVER_DIR" ]; then
  SPARK_SUBMIT_OPTIONS="$SPARK_SUBMIT_OPTIONS
    --master $1 --deploy-mode cluster
    --conf spark.yarn.submit.waitAppCompletion=false
    --files $appdir/log4j-cluster.properties,$conffile"
  JAR_FILE="$appdir/spark-job-server.jar"
  CONF_FILE=$(basename $conffile)

# use files in REMOTE_JOBSERVER_DIR
elif [ $2 == "cluster" ]; then
  SPARK_SUBMIT_OPTIONS="$SPARK_SUBMIT_OPTIONS
    --master $1 --deploy-mode cluster
    --conf spark.yarn.submit.waitAppCompletion=false"
  JAR_FILE="$REMOTE_JOBSERVER_DIR/spark-job-server.jar"
  CONF_FILE="$REMOTE_JOBSERVER_DIR/$(basename $conffile)"

# client mode, use files from app dir
else
  JAR_FILE="$appdir/spark-job-server.jar"
  CONF_FILE="$conffile"
  GC_OPTS="$GC_OPTS -Xloggc:$5/gc.out"
fi

if [ -n "$6" ]; then
  SPARK_SUBMIT_OPTIONS="$SPARK_SUBMIT_OPTIONS --proxy-user $6"
fi

if [ "$SEPARATE_EXECUTOR_LOGGING" = "true" ]
then
  export EXECUTOR_LOGGING_OPTS=""
else
  export EXECUTOR_LOGGING_OPTS="$LOGGING_OPTS"
fi

if [ -n "$JOBSERVER_KEYTAB" ]; then
  SPARK_SUBMIT_OPTIONS="$SPARK_SUBMIT_OPTIONS --keytab $JOBSERVER_KEYTAB"
fi

cmd='$SPARK_HOME/bin/spark-submit --class $MAIN --driver-memory $JOBSERVER_MEMORY
      --conf "spark.executor.extraJavaOptions=$EXECUTOR_LOGGING_OPTS"
      $SPARK_SUBMIT_OPTIONS
      --driver-java-options "$GC_OPTS $JAVA_OPTS $LOGGING_OPTS $CONFIG_OVERRIDES $SPARK_SUBMIT_JAVA_OPTIONS"
      $JAR_FILE $3 $4 $CONF_FILE'

eval $cmd 2>&1 > $5/spark-job-server.out

