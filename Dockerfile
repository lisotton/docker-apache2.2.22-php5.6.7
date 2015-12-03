FROM debian:jessie

ENV HTTPD_VERSION 2.2.22
ENV PHP_VERSION 5.6.7

ENV HTTPD_PREFIX /usr/local/apache2
ENV PATH $PATH:$HTTPD_PREFIX/bin
RUN mkdir -p "$HTTPD_PREFIX" \
  && chown www-data:www-data "$HTTPD_PREFIX"
WORKDIR $HTTPD_PREFIX

ENV HTTPD_BZ2_URL http://archive.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.bz2

ENV PHP_INI_DIR /usr/local/etc/php
RUN mkdir -p $PHP_INI_DIR/conf.d

ENV PHP_EXTRA_CONFIGURE_ARGS --with-apxs2=/usr/local/apache2/bin/apxs

ENV GPG_KEYS 0BD78B5F97500D450838F95DFE857D9A90D90EC1 6E4F6AB321FDC07F2C332E3AC2BF0BC433CFC8B3
RUN set -xe \
	&& for key in $GPG_KEYS; do \
		gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done

COPY docker-php-ext-* /usr/local/bin/

# install httpd runtime dependencies
# https://httpd.apache.org/docs/2.2/install.html#requirements
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		libapr1 \
		libaprutil1 \
		libapr1-dev \
		libaprutil1-dev \
		libpcre++0 \
		libssl1.0.0 \
	&& rm -r /var/lib/apt/lists/*

# PHP persistent / runtime deps
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    librecode0 \
    libsqlite3-0 \
    libxml2 \
    libpng12-dev \
		libjpeg-dev \
		libpq-dev \
  && rm -r /var/lib/apt/lists/*

RUN buildDeps=' \
		bzip2 \
		libpcre++-dev \
		libcurl4-openssl-dev \
		libreadline6-dev \
		librecode-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		xz-utils \
		gcc \
		pkg-config \
		make \
		autoconf \
	' \
	set -x \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends $buildDeps \
	&& rm -r /var/lib/apt/lists/* \
	&& curl -SL "$HTTPD_BZ2_URL" -o httpd.tar.bz2 \
	&& mkdir -p src/httpd \
	&& tar -xvf httpd.tar.bz2 -C src/httpd --strip-components=1 \
	&& rm httpd.tar.bz2* \
	&& cd src/httpd \
	&& ./configure --enable-so --enable-ssl --prefix=$HTTPD_PREFIX \
	&& make -j"$(nproc)" \
	&& make install \
	&& cd ../../ \
	&& rm -r src/httpd \
	&& sed -ri ' \
		s!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g; \
		s!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g; \
		' /usr/local/apache2/conf/httpd.conf \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc \
	&& gpg --verify php.tar.xz.asc \
	&& mkdir -p /usr/src/php \
	&& tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
	&& rm php.tar.xz* \
	&& cd /usr/src/php \
	&& ./configure \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		$PHP_EXTRA_CONFIGURE_ARGS \
		--disable-cgi \
		--enable-mysqlnd \
		--with-curl \
		--with-openssl \
		--with-readline \
		--with-recode \
		--with-zlib \
		--with-mysql \
	&& make -j"$(nproc)" \
	&& make install \
	&& { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
	&& make clean \
	&& docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
	&& docker-php-ext-install gd mbstring pdo pdo_mysql pdo_pgsql zip \
	&& apt-get purge -y --auto-remove $buildDeps

COPY httpd-foreground /usr/local/bin/

RUN mv /usr/local/apache2/conf/httpd.conf /usr/local/apache2/conf/httpd.conf.dist
COPY httpd.conf /usr/local/apache2/conf/httpd.conf

EXPOSE 80
CMD ["httpd-foreground"]
