#!/bin/bash
########################################################################################################################
SCRIPT_NAME="INSTALL-MONGODB"
########################################################################################################################

###############################################################################
## INICIO
###############################################################################
## LOG
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DATE=$(date +%m-%d-%Y_%H-%M)Hs
export LOG=$DIR/LOG-$SCRIPT_NAME-$DATE.log
echo "--------------------------------------------------------" 
echo "SCRIPT: $SCRIPT_NAME"
echo "INICIO: $DATE" 
echo "--------------------------------------------------------" 

###############################################################################
## DISCO
###############################################################################
echo "--------------------------------------------------------" 
echo "DISCO" | tee -a $LOG
echo "--------------------------------------------------------" 
DISK=/dev/sdb
DATA=/data
echo "Buscando Device Adcional: $DISK" | tee -a $LOG
if [ -e $DISK ]; then
  echo "Instalando xfsdump..." | tee -a $LOG
	 yum -y install xfsdump 2>> $LOG && echo "OK" | tee -a $LOG || { echo " ! ERROR" | tee -a $LOG ; exit 1; }
  echo "Formateando en XFS..."
	 mkfs.xfs $DISK 2>> $LOG && echo "OK" | tee -a $LOG || { echo " ! ERROR" | tee -a $LOG ; exit 1; }
  echo "Mount en $DATA"
	 mkdir $DATA
	echo "$DISK $DATA xfs defaults,auto,noatime,noexec 0 0" |  tee -a /etc/fstab
	 mount -a 2>> $LOG && echo "OK" | tee -a $LOG || { echo " ! ERROR" | tee -a $LOG ; exit 1; }
  echo "Seteando blockdev..." | tee -a $LOG
   blockdev --setra 32 $DISK
  echo 'ACTION=="add", KERNEL=="'"$DISK"'", ATTR{bdi/read_ahead_kb}="16"' |  tee -a /etc/udev/rules.d/85-ebs.rules
else
	echo " ! ERROR: NO ENCUENTRO: $DISK" | tee -a $LOG
	echo "Sigo en la raiz..." | tee -a $LOG
   mkdir $DATA
fi

###############################################################################
## MONGODB
###############################################################################
echo "--------------------------------------------------------" 
echo "MONGODB" | tee -a $LOG
echo "--------------------------------------------------------" 
echo "Agregando Repositorio..." 
echo "[mongodb-org-3.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2013.03/mongodb-org/3.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-3.2.asc" |  tee -a /etc/yum.repos.d/mongodb-org-3.2.repo
 yum -y update 

echo "Instalando MongoDB..." | tee -a $LOG
 yum install -y mongodb-org-server-3.2.12 mongodb-org-shell-3.2.12 mongodb-org-tools-3.2.12

echo "Generando Directorios..." | tee -a $LOG
 mkdir -p /data/db /data/logs /data/journal && \
 chown mongod:mongod /data/db /data/logs /data/journal && \
 ln -s /data/journal /data/db/journal && \
 sed -i 's/dbPath:.*/dbPath: \/data\/db/g' /etc/mongod.conf && \
 sed -i 's/path:.*/path: \/data\/logs\/mongod.log/g' /etc/mongod.conf 2>> $LOG \
  && echo "OK" | tee -a $LOG || { echo " ! ERROR" | tee -a $LOG ; exit 1 ; }

echo "Configurando Linux limits..."
echo '* soft nofile 64000
* hard nofile 64000
* soft nproc 64000
* hard nproc 64000' |  tee /etc/security/limits.d/90-mongodb.conf

echo "Disable Transparent Hugepages..."
# https://docs.mongodb.com/manual/tutorial/transparent-huge-pages/#transparent-huge-pages-thp-settings

 tee -a /etc/init.d/disable-transparent-hugepages <<'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          disable-transparent-hugepages
# Required-Start:    $local_fs
# Required-Stop:
# X-Start-Before:    mongod mongodb-mms-automation-agent
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Disable Linux transparent huge pages
# Description:       Disable Linux transparent huge pages, to improve
#                    database performance.
### END INIT INFO

case $1 in
  start)
    if [ -d /sys/kernel/mm/transparent_hugepage ]; then
      thp_path=/sys/kernel/mm/transparent_hugepage
    elif [ -d /sys/kernel/mm/redhat_transparent_hugepage ]; then
      thp_path=/sys/kernel/mm/redhat_transparent_hugepage
    else
      return 0
    fi

    echo 'never' > ${thp_path}/enabled
    echo 'never' > ${thp_path}/defrag

    re='^[0-1]+$'
    if [[ $(cat ${thp_path}/khugepaged/defrag) =~ $re ]]
    then
      # RHEL 7
      echo 0  > ${thp_path}/khugepaged/defrag
    else
      # RHEL 6
      echo 'no' > ${thp_path}/khugepaged/defrag
    fi

    unset re
    unset thp_path
    ;;
esac
EOF
 chmod 0755 /etc/init.d/disable-transparent-hugepages && \
 chown root:root /etc/init.d/disable-transparent-hugepages && \
 chkconfig --add disable-transparent-hugepages && \
 chkconfig disable-transparent-hugepages on && \
 service disable-transparent-hugepages start 

echo "Sacando Restriccion bindIp ..." 
 sed -i 's/bindIp:.*/#bindIp: 127.0.0.1 /g' /etc/mongod.conf 

echo "Desactivando Ejecucion Automatica de MongoDB ..."
 chkconfig mongod off 