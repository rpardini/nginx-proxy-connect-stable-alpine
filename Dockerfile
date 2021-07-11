FROM alpine:3.12.7

# apk upgrade in a separate layer (musl is huge)
RUN apk upgrade --no-cache --update

# Bring in tzdata and runtime libs into their own layer
RUN apk add --no-cache --update tzdata pcre zlib libssl1.1

# If set to 1, enables building debug version of nginx, which is super-useful, but also heavy to build.
ARG DEBUG_BUILD="1"
ENV DO_DEBUG_BUILD="$DEBUG_BUILD"

ENV NGINX_VERSION 1.20.1

# nginx layer
RUN CONFIG="\
		--prefix=/etc/nginx \
		--sbin-path=/usr/sbin/nginx \
		--modules-path=/usr/lib/nginx/modules \
		--conf-path=/etc/nginx/nginx.conf \
		--error-log-path=/var/log/nginx/error.log \
		--http-log-path=/var/log/nginx/access.log \
		--pid-path=/var/run/nginx.pid \
		--lock-path=/var/run/nginx.lock \
		--http-client-body-temp-path=/var/cache/nginx/client_temp \
		--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
		--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
		--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
		--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
		--user=nginx \
		--group=nginx \
		--with-http_ssl_module \
		--with-http_realip_module \
		--with-http_addition_module \
		--with-http_sub_module \
		--with-http_gunzip_module \
		--with-http_gzip_static_module \
		--with-http_random_index_module \
		--with-http_secure_link_module \
		--with-http_stub_status_module \
		--with-http_auth_request_module \
		--with-threads \
		--with-stream \
		--with-stream_ssl_module \
		--with-stream_ssl_preread_module \
		--with-stream_realip_module \
		--with-http_slice_module \
		--with-compat \
		--with-file-aio \
		--with-http_v2_module \
	" \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --update --virtual .build-deps gcc libc-dev make openssl-dev pcre-dev zlib-dev linux-headers patch curl git  \
 	&& curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
	&& git clone https://github.com/chobits/ngx_http_proxy_connect_module.git /usr/src/ngx_http_proxy_connect_module \
	&& cd /usr/src/ngx_http_proxy_connect_module && export PROXY_CONNECT_MODULE_PATH="$(pwd)" && cd - \
	&& CONFIG="$CONFIG --add-module=$PROXY_CONNECT_MODULE_PATH" \
	&& mkdir -p /usr/src \
	&& tar -zxC /usr/src -f nginx.tar.gz \
	&& rm nginx.tar.gz \
	&& cd /usr/src/nginx-$NGINX_VERSION \
	&& patch -p1 < $PROXY_CONNECT_MODULE_PATH/patch/proxy_connect_rewrite_101504.patch \
	&& [ "a$DO_DEBUG_BUILD" == "a1" ] && { echo "Bulding DEBUG" &&  ./configure $CONFIG --with-debug && make -j$(getconf _NPROCESSORS_ONLN) && mv objs/nginx objs/nginx-debug ; } || { echo "Not building debug"; } \
	&& { echo "Bulding RELEASE" && ./configure $CONFIG  && make -j$(getconf _NPROCESSORS_ONLN) && make install; } \
	&& ls -laR objs/addon/ngx_http_proxy_connect_module/ \
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir -p /usr/share/nginx/html/ \
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	&& [ "a$DO_DEBUG_BUILD" == "a1" ] && { install -m755 objs/nginx-debug /usr/sbin/nginx-debug; } || { echo "Not installing debug..."; } \
	&& mkdir -p /usr/lib/nginx/modules \
	&& ln -s /usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx* \
	&& rm -rf /usr/src/nginx-$NGINX_VERSION \
	\
	# Remove -dev apks and sources
	&& apk del .build-deps gcc libc-dev make openssl-dev pcre-dev zlib-dev linux-headers patch curl git && rm -rf /usr/src \
	\
	# forward request and error logs to docker log collector
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

#RUN ls -laR /usr/share/nginx /etc/nginx /etc/nginx/modules/ /usr/lib/nginx

COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf

# Basic sanity testing.
RUN nginx -V 2>&1 && nginx -t && ldd /usr/sbin/nginx && apk list && rm -rf /run/nginx.pid /var/cache/nginx/*_temp

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
