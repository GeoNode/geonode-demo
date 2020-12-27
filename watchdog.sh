#!/bin/bash

#The MIT License
#
#Copyright (c) 2011 GeoSolutions S.A.S.
#http://www.geo-solutions.it
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.

############################################################
# author: carlo cancellieri - ccancellieri@geo-solutions.it
# date: 7 Apr 2011
#
# simple watchdog for webservice
############################################################

# the url to use to test the service
# !make sure to implement the url_test logic also into the bottom function
#URL=http://192.168.1.106:8484/figis/geoserver/styles/default_point.sld

GSURL="https://master.demo.geonode.org/geoserver/ows?service=wcs&version=1.0.0&request=GetCapabilities"
# WFSURL="$GSURL/wfs?service=wfs&version=1.1.0&request=GetFeature&typeName=topp:tasmania_cities&propertyName=ADMIN_NAME&maxfeatures=1"

#set the connection timeout (in seconds)
TIMEOUT=30

# seconds to wait to recheck the service (this is not cron)
# tomcat restart time
TOMCAT_TIMEOUT=50

# used to filter the process (to get the pid)
# use: ps -efl
# to see what you have to filter
FILTER="geoserver"

# the service to restart
# should be a script placed here:
# /etc/init.d/
# 
SERVICE="tomcat"
# CMD_START="sudo systemctl start ${SERVICE}"
# CMD_STOP="sudo systemctl stop ${SERVICE}"
CMD_START="docker restart geoserver4geonode_master"
CMD_STOP="docker stop geoserver4geonode_master"

# the output file to use as log
# must exists otherwise the stdout will be used
# NOTE: remember to logrotate this file!!!
LOGFILE="/var/log/watchdog.log.geoserver"

# maximum tries to perform a quick restart
# when the service fails to be started a quick (30 sec)
# restart will be tried at least $RETRY times
# if restart fails RETRY times  the script ends returning '100'
RETRY=3

################### WATCHDOG #####################

url_test()
{
   TMPFILE=/tmp/urltest
   rm $TMPFILE
   # OUTPUT=$(wget -O - -T "${TIMEOUT}" --proxy=off ${WFSURL} >> "${LOGFILE}" 2>&1)
   # curl --max-time $TIMEOUT $WFSURL > $TMPFILE 2>> $LOGFILE
   #docker exec ${CONTAINER} curl -s --max-time $TIMEOUT $WMSURL > $TMPFILE 2>> $LOGFILE
   #docker exec ${CONTAINER} wget -O - -T 5 -o "/dev/null" --proxy=off ${WFSURL}


   echo "running following comand: curl --max-time $TIMEOUT $GSURL > $TMPFILE 2>> $LOGFILE"
   #docker exec ${CONTAINER} curl -s --max-time $TIMEOUT $GNURL > $TMPFILE 2>> $LOGFILE
   #curl --max-time $TIMEOUT $GNURL > $TMPFILE 2>> $LOGFILE
   wget -t 3 -T $TIMEOUT -O $TMPFILE $GSURL

   if grep 'wcs:WCS_Capabilities' $TMPFILE ; then
        return 0
   else
        return 1
   fi
}


times=0;

if [ ! -e "$LOGFILE" ]; then
	LOGFILE="/dev/stdout"
	echo "`date` WatchDog output file: DOES NOT EXIST: using ${LOGFILE}" >> "${LOGFILE}"
else
	echo "`date` WatchDog setting output to: ${LOGFILE}" >> "${LOGFILE}"
fi


#loop
while [ "$times" -lt "$RETRY" ]
do
  	url_test

        #testing on url_test exit code
	if [ "$?" -eq 0 ] ; then
		echo "`date` WatchDog Status: OK -> $SERVICE is responding at URL $GSURL" >> $LOGFILE
		exit 0;
	else
		echo "`date` WatchDog Status: FAIL -> $SERVICE is NOT responding properly at URL $GSURL" >> $LOGFILE
		echo "`date` WatchDog Action: Stopping service $SERVICE" >> $LOGFILE

		PIDFILE=`${CMD_STOP} |awk '/PID/{gsub(".*[(]","",$0);gsub("[)].*","",$0); print $0}'`
		if [ -e "$PIDFILE" ]; then
			echo "`date` removing pid file: $PIDFILE" >> "${LOGFILE}"
			rm "$PIDFILE" >> "${LOGFILE}" 2>&1
		fi
		sleep 1


		for thepin in $(ps -eo pid,cmd | grep org.apache.catalina.startup.Bootstrap | grep "$FILTER" | grep -v grep | cut -f 1 -d \  ) ; do
#`ps -efl | awk -v FILTER="${FILTER}" '!/awk/&&/org.apache.catalina.startup.Bootstrap/{if ($0 ~ FILTER) {print $4}}'`; do
			echo "`date` WatchDog Action: Stop failed -> TERMinating service $SERVICE (pid: ${thepin})" >> $LOGFILE
			kill -15 $thepin >> $LOGFILE 2>&1
			sleep "$TIMEOUT"
			while [ "${thepin}" = "`ps -efl | awk -v FILTER="${FILTER}" '!/awk/&&/org.apache.catalina.startup.Bootstrap/{if ($0 ~ FILTER) {print $4}}'`" ];
			do 
				echo "`date` WatchDog Action: TERM failed -> KILLing service $SERVICE (pid: ${thepin})" >> "${LOGFILE}"
				kill -9 "${thepin}" >> "${LOGFILE}" 2>&1
				sleep "$TIMEOUT"
			done
		done

		echo "`date` WatchDog Action: Starting service ${SERVICE}" >> "${LOGFILE}"

		${CMD_START} >> "${LOGFILE}" 2>&1
		if [ "$?" -eq 0 ]; then
			echo "`date` WatchDog Action: service ${SERVICE} STARTED" >> "${LOGFILE}"
			times=`expr "$times" "+" "1"`
			# give tomcat time to start
			sleep "$TOMCAT_TIMEOUT"
			# let's retest the connection STILL NOT RETURN
		elif [ "$?" -eq 1 ]; then
			times=`expr "$times" "+" "1"`
			echo "`date` WatchDog Action: service ${SERVICE} ALREADY STARTED (WHAT'S HAPPENING? -> quick retry ($times/$RETRY))" >> "${LOGFILE}"
			# give tomcat time to start
			sleep "$TOMCAT_TIMEOUT"
		else
			times=`expr "$times" "+" "1"`
			echo "`date` WatchDog Action: Starting service FAILED ${SERVICE} (WHAT'S HAPPENING? -> quick retry ($times/$RETRY))" >> "${LOGFILE}"
			# give tomcat time to start
			sleep "$TOMCAT_TIMEOUT"
		fi
	fi
done
echo "`date` WatchDog Action: Starting service FAILED ${SERVICE} (WHAT's HAPPENING? -> exit (status: 100))" >> "${LOGFILE}"
return 100

