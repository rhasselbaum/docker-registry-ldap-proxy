docker-registry-ldap-proxy
==========================

Wraps a [private Docker registry](https://registry.hub.docker.com/_/registry/) with an HTTPS proxy that allows anyone to read from the registry, but restricts updates to only authorized users in an LDAP database. This image was designed specifically for Active Directory in a company setting, but should work with any similarly configured LDAP service. Suggestions to improve the image are welcome on my [GitHub page](https://github.com/rhasselbaum/docker-registry-ldap-proxy).

Prerequisites
=============

Before starting, you should have:

1. A functioning private Docker registry. The official `registry` image works fine.
2. An X.509 certificate and private key for the proxy server, signed by a CA.
3. CA certificate of the LDAP (Active Directory) servers for SSL/TLS connections. You weren't planning to send credentials unencrypted, were you? ;-)
4. At least one LDAP server such as an Active Directory domain controller. Some installations may also require a set of user credentials authorized to make LDAP queries. This user is not the same as the users who are allowed to update the registry.

How it works
============
With a plain `registry` container and no proxy, the Docker daemon and other web service clients connect directly to the registry on port 5000 or whatever alternative port you've configured. With the proxy, clients instead connect to the proxy over SSL/TLS. The proxy performs authorization checks and then forwards requests to the real registry. The real registry should not be exposed on the public network interface in this scenario. Instead, you expose the proxy and link it to the registry over the private Docker bridge. You can use [container linking](https://docs.docker.com/userguide/dockerlinks/) for this purpose.

The proxy is simply an Apache HTTP server that forwards all GET requests to the registry, and conditionally forwards other requests that update data (POST, PUT, DELETE). In the latter case, the proxy authenticates credentials in the HTTP Basic Auth header against the LDAP server and checks to see if the authenticated principal matches a specific user, group, or other criteria. If so, the proxy forwards the request to the registry. If you want more complicated authorization rules, you can modify the Apache configuration in the `reg-proxy.conf` file.

Using the image
===============

The instructions below explain how to use the `docker-registry-ldap-proxy` image. You can either create a container directly or create a child image with your configuration. Your choice.

Set up the certificates
-----------------------

You first need to obtain an X.509 certificate and private key for SSL/TLS connections to the proxy. Self-signed certificates won't work with Docker, but you can create a private Certificate Authority (CA) and sign your own certificates for testing using a tool like [EasyRSA](http://openvpn.net/index.php/open-source/documentation/miscellaneous/77-rsa-key-management.html). For production, you'll probably want a certificate signed by your organization's CA or a public CA.

In this example, we will assume the certificate file is called `reg-proxy-cert.pem` and the key is `reg-proxy-key.pem`. You'll also need a copy of the CA certificate used to sign the LDAP server's certificate. We'll assume that's called `ldap-ca-cert.pem`. Now, make a new directory and arrange your certificate and key files in subdirectories like so:

```
<data_dir>
  +--certs
  | +--reg-proxy-cert.pem
  | +--ldap-ca-cert.pem
  +--keys
    +--reg-proxy-key.pem
```

If you clone my [Git repository](http://openvpn.net/index.php/open-source/documentation/miscellaneous/77-rsa-key-management.html) you can put these subdirectories inside the repository directory. Both `certs` and `keys` are listed in `.gitignore`.

Run the container
-----------------

Once you have the file structure above, change directory to `<data_dir>`. Then you can start a minimal proxy container like this:

```
docker run -d -p 443:443 \
  -v `pwd`/certs:/etc/ssl/certs \
  -v `pwd`/keys:/etc/ssl/private \
  --link registry:registry \
  -e SERVER_NAME=`hostname -f` \
  -e AUTH_LDAP_URL="ldap://dc-01.example.com:3268/?userPrincipalName?sub" \
  -e REQUIRE_AUTHZ_USERS=registry.admin@example.com \
  rhasselbaum/docker-registry-ldap-proxy
```

This starts the proxy listening on the host's port 443 (HTTPS) and links it to an existing registry container named `registry`. The `AUTH_LDAP_URL` environment variables specifies the LDAP URL and is equivalent to Apache's [mod_authnz_ldap](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html) directive of the [same name](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html#authldapurl). By default, the proxy will use STARTTLS to force an encrypted connection on the LDAP port.

The full list of recognized environment variables with defaults is given below. Most of these correspond to Apache configuration directives and the links take you to the corresponding documentation. The defaults try to be sensible except for `AUTH_LDAP_URL` and `REQUIRE_AUTHZ_USERS`, which must be specified for a minimally functional proxy.

* [LOG_LEVEL](http://httpd.apache.org/docs/2.4/mod/core.html#loglevel) = `warn`
  Apache HTTP server log level. Setting this to `debug` or one of the `traceX` levels can help you troubleshoot problems. Log entries are written to standard output and can be read with `docker logs`.
* [SERVER_NAME](http://httpd.apache.org/docs/2.4/mod/core.html#servername) = `localhost`
  The fully-qualified domain name or URL remote clients use to access this proxy server. This should match the Common Name (CN) in the proxy's certificate.
* [LDAP_TRUSTED_GLOBAL_CERT_PATH](http://httpd.apache.org/docs/2.4/mod/mod_ldap.html#ldaptrustedglobalcert) = `/etc/ssl/certs/ldap-ca-cert.pem`
  Directory path and file name of the trusted CA certificate of the LDAP server(s) in PEM format. This file must exist, but if you want to disable SSL/TLS on the LDAP connection for testing, you can set this to `/dev/null` and set `LDAP_TRUSTED_MODE` to `NONE`.
* [LDAP_TRUSTED_MODE](http://httpd.apache.org/docs/2.4/mod/mod_ldap.html#ldaptrustedmode) = `TLS`
  Encryption mode for LDAP server connections. `TLS` uses STARTTLS to upgrade an unencrypted connection on the default port to an encrypted one. `SSL` typically runs on a dedicated port. `NONE` means no encryption and should only be used for testing. When setting this to `NONE`, you may also set `LDAP_TRUSTED_GLOBAL_CERT_PATH` to `/dev/null` to avoid having to provide a certificate for LDAP.
* [LDAP_LIBRARY_DEBUG](http://httpd.apache.org/docs/2.4/mod/mod_ldap.html#ldaplibrarydebug) = `0`
  Debug log level for the LDAP library. Apache recommends 7 for verbose output. Log entries are written to standard output and can be read with `docker logs`. Also see `LOG_LEVEL`.
* [SSL_CERTIFICATE_FILE](http://httpd.apache.org/docs/current/mod/mod_ssl.html#sslcertificatefile) = `/etc/ssl/certs/reg-proxy-cert.pem`
  Certificate of this registry proxy. It must be signed by a CA that is trusted by its clients (e.g. the Docker daemon). Self-signed certificates will not work with Docker.
* [SSL_CERTIFICATE_KEY_FILE](http://httpd.apache.org/docs/current/mod/mod_ssl.html#sslcertificatekeyfile) = `/etc/ssl/private/reg-proxy-key.pem`
  Private key matching the certificate of this registry proxy.
* REGISTRY_PORT_5000_TCP_ADDR = `registry`
  Name or IP address of the Docker registry we are wrapping. You can set this explicitly or use Docker [container linking](https://docs.docker.com/userguide/dockerlinks/) with `registry` as the alias (e.g. `docker run --link <your_container>:registry [...]`).
* REGISTRY_PORT_5000_TCP_PORT = `5000`
  Plain HTTP listener port of the Docker registry we are wrapping. You can set this explicitly or use Docker [container linking](https://docs.docker.com/userguide/dockerlinks/) with `registry` as the alias (e.g. `docker run --link <your_container>:registry [...]`).
* [AUTH_LDAP_URL](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html#authldapurl) = `ldap://dc-01.example.com:3268/?userPrincipalName?sub`
The LDAP server URL and search parameters for LDAP queries. You **MUST** override this setting to have a functional proxy. The default shows the [typical form](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html#activedirectory) for queries using Active Directory's Global Catalog. Also make sure the setting of `LDAP_TRUSTED_MODE` is compatible with the scheme specified here (e.g. `ldap://` for STARTTLS or unencrypted; `ldaps://` for SSL). By default, the connection is made over unsecured port 3268, but immediately upgraded to a secure connection using STARTTLS.
* [AUTH_LDAP_BIND_DN](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html#authldapbinddn) (no default)
  DN used to bind to the server when making LDAP queries. In Active Directory, this is typically a service account in the format `user@example.com`. It is not necessarily the same as the user or group authorized to make changes to the Docker registry.

> Due to an [Apache issue](https://issues.apache.org/bugzilla/show_bug.cgi?id=57506), this setting must be specified even though it is technically optional. Active Directory normally requires it anyway.

* [AUTH_LDAP_BIND_PASSWORD](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html#authldapbindpassword) (no default)
  Password used in conjunction with the account specified in `AUTH_LDAP_BIND_DN`. If you don't want to pass the password as a plaintext environment variable, you can instead copy a file with the password into the container and use Apache's `exec:` syntax to fetch it. See the linked documentation for details.

> Due to an [Apache issue](https://issues.apache.org/bugzilla/show_bug.cgi?id=57506), this setting must be specified even though it is technically optional. Active Directory normally requires it anyway.

* [REQUIRE_AUTHZ_TYPE](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html#requiredirectives) = `ldap-user`
  The filtering strategy used to identify the user(s) authorized to make changes to the registry. Examples include `ldap-user`, `ldap-group`, and `ldap-filter`. Consult the linked Apache documentation for all possibilities. This setting tells the proxy how to interpret the value in `REQUIRE_AUTHZ_USERS`.
* [REQUIRE_AUTHZ_USERS](http://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html#requiredirectives) = `registry.admin@example.com`
  User name, group name, or any other string compatible with the `REQUIRE_AUTHZ_TYPE` setting that specifies the user(s) authorized to make changes to the registry. When specifying a user name in Active Directory Global Catalog, it should be of the form `user@example.com`.

Naturally, you can build child images with your own `Dockerfile` if you don't want to specify environment variables in `docker run`.

Integration with Docker daemon
==============================

If you are only reading from the registry, there should be no noticeable difference between accessing the registry directly and through the proxy. You use standard commands like `docker pull` and `docker run` to download images, for example.

However, if you get an error that mentions an unknown CA certificate, you must register the CA that signed the proxy's SSL/TLS certificate with the Docker daemon. Docker's error message suggests you can do this by dropping the CA certificate file in a `/etc/docker/certs.d/<registry>` directory. However, this is [not always effective](https://github.com/docker/docker/issues/10150) and you may need to add the CA certificate to the Linux host's global certificate store. The procedure varies by host distro. Here are the steps for **Debian/Ubuntu** variants:

1. Copy the CA cert file (e.g. `acme-corporation-ca.crt`) to `/usr/local/share/ca-certificates`.
2. Run `sudo update-ca-certificates`.
3. Restart the Docker daemon with `sudo service docker.io restart`.

On **RHEL/Fedora/CentOS** and similar:

1. Copy the CA cert file (e.g. `acme-corporation-ca.crt`) to `/etc/pki/ca-trust/source/anchors`.
2. Run `sudo update-ca-trust`.
3. Restart the Docker daemon with `sudo systemctl restart docker`.

Once certificate validation is working, you should be able to pull images from the proxy as an unauthenticated user.

Finally, let's deal with updates. In order to make changes to the registry, you need to authenticate as an authorized user. (That's the whole point, after all.) Use `docker login` for this, specifying the user in `user@example.com` format if you're using AD Global Catalog. For example:

```
docker login -u registry.admin@example.com \
  -e registry.admin@example.com \
  docker.example.com
```
You will be prompted for a password. Strangely, `docker login` may report success even if the credentials are incorrect, so the real test is to try to push an image after login. If you get an error complaining about an unknown CA certificate, make sure you followed the instructions above to register the proxy's CA certificate with the Docker daemon.