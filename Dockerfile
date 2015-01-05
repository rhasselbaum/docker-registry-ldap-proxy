# A Docker registry proxy that authenticates against LDAP for updates.

FROM httpd:2.4
MAINTAINER Rob Hasselbaum <rob@hasselbaum.met>

COPY httpd.conf /usr/local/apache2/conf/httpd.conf
COPY cert.pem /etc/ssl/cert.pem
COPY key.pem /etc/ssl/key.pem
 
