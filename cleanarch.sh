#/bin/sh
############
# this shell script for clean db2 archive log ,it depends on hadr needed log ,and left 50 logs beftore that 
# (1) add check 1 module and add $3 parameter for justice the right directory of the arch log  . 
############
#first step : switch case and choose the better way to clean archive log 
############
###  sh /data/bin/cleanarch.sh db2ydjs mbidb "/data/db2_archive/db2ydjs/MBIDB/NODE0000/LOGSTREAM0000"
############ set all env
if [ -f /home/$1/sqllib/db2profile ]; then
    . /home/$1/sqllib/db2profile
fi

DBNAME=`echo $2 | tr 'a-z' 'A-Z'`
V_DATE=`date +"%Y%m%d"`
archpath=`db2 get db cfg for $2 | grep LOGARCHMETH1 | awk -F ':' '{print $NF}'`


db2 connect to $2

ArcDirTMP=`db2 -x  "select location from sysibmadm.db_history where operation = 'X' and end_time  > '$V_DATE'  and operationtype = '1' with ur " `

ArcDir=`printf "$ArcDirTMP" |tail -n1 | xargs dirname`

### check 1 
CHK_1=`echo $1 | tr 'a-z' 'a-z'`
CHK_2=`echo $2 | tr 'a-z' 'A-Z'`

archeck=`echo  "$ArcDir" | xargs dirname`
if [[ $3 == ${archeck}	 &&   ${archeck} ==  ${archpath}$CHK_1/$CHK_2*      ]] ; then 
	:
	
else 
	printf " error arch path \n" 
        printf "${archpath}$CHK_1/$CHK_2\n"
        printf "$3\n"
        printf "$archeck\n"
        printf "$ArcDir\n"

	exit 1

fi


### check 1


#####add  alternative way  to fetch db2 archive path 

curLogIdTMP=` su - $1 -c " db2pd -d ${DBNAME} -hadr " `
curLogId=`printf   "$curLogIdTMP" | grep STANDBY_LOG_FILE | awk '{print $3}' | awk -F"." '{printf("%d", substr($1,2))}'`
HADR_STAT=`printf "$curLogIdTMP" | grep -iq "= DISCONNECTED" && printf "no"  `
HADR_STAT=`printf "$curLogIdTMP" | grep -iq "= CONNECTED" && printf "yes" || printf "no"  `
HADR_ISRUN=`printf "$curLogIdTMP" | grep -iq "HADR is not active" && printf "no" || printf "yes"`
###########set all env

####check all will used variables 


final_guard()
{
########### if when this script run and check the directory used percent and run guard line for cleaning in emergency way .
if [ `uname` = "Linux" ] ; then 
	PERCENT=`df  -h $archpath | awk 'NR==2 {print $5}' | sed 's/\%//g'`
	printf "PERCENT:$PERCENT\n"
fi

if [ `uname` = "AIX" ] ;   then  
	PERCENT=`df  -g $archpath  | awk 'NR==2 {print $4}' | sed 's/\%//g'`
	printf "PERCENT:$PERCENT\n"
fi

if [ $PERCENT -gt 95 ] ; then 
	return 1
else 
	return 0
fi

}



###check all needed variables is not null 
if
[ -z "$DBNAME" ]    || 
[ -z "$V_DATE" ]    ||
[ -z "$archpath" ]  ||
[ -z "$ArcDir" ]    

then 
    {
    printf "ERROR: please check dbname , date , archpath , arch directory-------`date`\n"
    exit 1 
    }
fi    

printf "
	DBNAME=$DBNAME
	V_DATE=$V_DATE
	ARCHPATH=$archpath
	ArcDir=$ArcDir
	curLogId=$curLogId
	HADR_STAT=$HADR_STAT
	HADR_ISRUN=$HADR_ISRUN
	"

cd $ArcDir

###os utilities check
final_guard 

if [[ $? -eq 1 ]] ; then
	{
		v_final_guard=1
		printf "fire the final guard way\n"
	}
else 
	v_final_guard=0
fi

###normal speed clean 
for filnm in `ls -lrt S*.LOG | awk '{print substr($NF,0,length($NF)-4)}'`
do
       LogID=`echo $filnm | awk '{printf("%d", substr($0,2)+100)}'`

if   [[ $HADR_STAT = "yes" && $HADR_ISRUN = "yes" ]] ;then  
        if [ $curLogId -gt $LogID ]
        then
                echo "[`date`][NORMAL] [$curLogId - $LogID] Remove ${filnm}.LOG"
                rm -f ${filnm}.LOG 
        else
                echo "[`date`][NORMAL] [$curLogId - $LogID - ${filnm}.LOG] Remove task completed !!!\n\n"
                break
        fi

else  	   
###without hadr clean speed
	 if    [[ $HADR_STAT = "no" ||   $HADR_ISRUN = "no" ]] ; then
		curLogId=`ls -lrt S*.LOG | awk '{print substr($NF,0,length($NF)-4)}' | tail -n100 |head -n1| awk '{printf("%d", substr($0,2))}'` 
	     if [ $curLogId -gt $LogID ]
        	then    
                echo "[`date`][HADRBROK][$curLogId - $LogID] Remove ${filnm}.LOG"
                rm -f ${filnm}.LOG 
       	     else    
                echo "[`date`][HADRBROK][$curLogId - $LogID - ${filnm}.LOG] Remove task completed !!!\n\n"
                break   
             fi      
	fi
fi
done

###fire the 95 percent clean 
for filnm in `ls -lrt S*.LOG | awk '{print substr($NF,0,length($NF)-4)}'`

do 
        if [  $v_final_guard  -eq  1 ] ; then
		final_LogId=`ls -lrt S*.LOG | awk '{print substr($NF,0,length($NF)-4)}' | tail -n1 | awk '{printf("%d", substr($0,2))}'`
       		LogID=`echo $filnm | awk '{printf("%d", substr($0,2)+100)}'`

	     if [ $final_LogId -gt $LogID ]
        	then    
                echo "[`date`][FINAL][$final_LogId - $LogID] Remove ${filnm}.LOG"
                rm -f ${filnm}.LOG 
       	     else    
                echo "[`date`][FINAL][$final_LogId - $LogID - ${filnm}.LOG] Remove task completed !!!\n\n"
                break   
             fi      
	fi

done

### keep the old way to clean archlog

cd $ArcDir
find . -name "S0*.LOG" -mtime +1|xargs gzip  
find . -name "S0*.LOG.gz" -mtime +2|xargs rm -rf

