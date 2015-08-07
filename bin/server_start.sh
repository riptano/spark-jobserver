#!/bin/bash
# Script to start the job server
# Extra arguments will be spark-submit options, for example
#  ./server_start.sh --jars cassandra-spark-connector.jar
set -e

get_abs_script_path() {
  pushd . >/dev/null
  cd "$(dirname "$0")"
  appdir=$(pwd)
  popd  >/dev/null
}

get_abs_script_path

GC_OPTS="-XX:+UseConcMarkSweepGC
         -verbose:gc -XX:+PrintGCTimeStamps -Xloggc:$appdir/gc.out
         -XX:MaxPermSize=512m
         -XX:+CMSClassUnloadingEnabled "

JAVA_OPTS="-XX:MaxDirectMemorySize=512M
           -XX:+HeapDumpOnOutOfMemoryError -Djava.net.preferIPv4Stack=true
           -Dcom.sun.management.jmxremote.port=9999
           -Dcom.sun.management.jmxremote.authenticate=false
           -Dcom.sun.management.jmxremote.ssl=false"

MAIN="spark.jobserver.JobServer"

conffile="$(ls -1 "$appdir"/*.conf | head -1)"
if [ -z "$conffile" ]; then
  echo "No configuration file found"
  exit 1
fi

if [ -f "$appdir/settings.sh" ]; then
  . "$appdir/settings.sh"
else
  echo "Missing $appdir/settings.sh, exiting"
  exit 1
fi

if [ -z "$SPARK_HOME" ]; then
  echo "Please set SPARK_HOME or put it in $appdir/settings.sh first"
  exit 1
fi

pidFilePath=$appdir/$PIDFILE

if [ -f "$pidFilePath" ] && kill -0 "$(cat "$pidFilePath")"; then
   echo 'Job server is already running'
   exit 1
fi

if [ -z "$LOG_DIR" ]; then
  LOG_DIR=/tmp/job-server
  echo "LOG_DIR empty; logging will go to $LOG_DIR"
fi
mkdir -p $LOG_DIR

LOGGING_OPTS="-DLOG_DIR=$LOG_DIR"

export SPARK_SUBMIT_LOGBACK_CONF_FILE="$appdir/logback-server.xml"

# For Mesos
CONFIG_OVERRIDES=""
if [ -n "$SPARK_EXECUTOR_URI" ]; then
  CONFIG_OVERRIDES="-Dspark.executor.uri=$SPARK_EXECUTOR_URI "
fi
# For Mesos/Marathon, use the passed-in port
if [ "$PORT" != "" ]; then
  CONFIG_OVERRIDES+="-Dspark.jobserver.port=$PORT "
fi

if [ -z "$DRIVER_MEMORY" ]; then
	DRIVER_MEMORY=1G
fi

# This needs to be exported for standalone mode so drivers can connect to the Spark cluster
export SPARK_HOME

# DSE_BIN is set in settings.sh
"$DSE_HOME/bin/dse" spark-submit --class "$MAIN" --driver-memory 5G \
  --conf "spark.executor.extraJavaOptions=$LOGGING_OPTS" \
  --driver-java-options "$GC_OPTS $JAVA_OPTS $LOGGING_OPTS $CONFIG_OVERRIDES" \
  "$@" "$appdir/spark-job-server.jar" "$conffile" 2>&1 &
echo "$!" > "$pidFilePath"
