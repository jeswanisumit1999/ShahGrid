#!/bin/sh
DOMAIN="app.shahgrid.com"
echo "hello \${DOMAIN}" > test.template
envsubst '\$DOMAIN' < test.template
echo ""
envsubst '$$DOMAIN' < test.template
echo ""
envsubst '\${DOMAIN}' < test.template
