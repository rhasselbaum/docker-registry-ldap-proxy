docker-registry-ldap-proxy
==========================

Wraps a private `docker-registry` with an HTTPS proxy that requires LDAP authentication for write operations, but allows anonymous read access. The goal is to integrate a private registry with Active Directory in a company setting. We use the Apache HTTP Server for the proxy, since LDAP authentication is available via a prebuilt module.
