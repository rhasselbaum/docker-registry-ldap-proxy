#!/bin/bash
. /etc/apache2/envvars

# Default values if registry wasn't specified through linking or env vars.
if [ -z "$REGISTRY_PORT_5000_TCP_ADDR" ]; then
  export REGISTRY_PORT_5000_TCP_ADDR=registry
fi
if [ -z "$REGISTRY_PORT_5000_TCP_PORT" ]; then
  export REGISTRY_PORT_5000_TCP_PORT=5000
fi

exec apache2 -D FOREGROUND
