FROM amazonlinux:2016.09
RUN yum update -y
RUN yum -y install shadow-utils
RUN yum -y install initscripts
RUN mkdir -p /data/db
RUN mkdir -p /etc/security/limits.d
COPY createDB.sh /
RUN sh /createDB.sh
