# Copyright (C) 2012 - 2016 Tim Düsterhus
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

FROM	node:18

RUN	mkdir -p /usr/src/app/

WORKDIR	/usr/src/app

COPY	package.json package-lock.json /usr/src/app/
RUN	npm ci
COPY	. /usr/src/app/

USER	node
EXPOSE	9001

CMD	[ "node", "server.js" ]
