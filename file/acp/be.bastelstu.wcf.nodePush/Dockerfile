FROM node:onbuild

MAINTAINER Tim Düsterhus

RUN	groupadd -r node \
	&& useradd -r -g node node \
	&& chown -R node:node /usr/src/app

EXPOSE 9001
EXPOSE 9002
USER node
