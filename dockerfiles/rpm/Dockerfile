FROM centos:centos6

MAINTAINER Michael Hoglan michaelh@tune.com

RUN yum install -y rpm-build && \
	mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS} && \
	echo '%_topdir %(echo $HOME)/rpmbuild' > ~/.rpmmacros && \
	yum clean all

WORKDIR /root/rpmbuild/
