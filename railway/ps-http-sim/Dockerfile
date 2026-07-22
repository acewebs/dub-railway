# Wrapper image for ps-http-sim on Railway.
# The upstream ghcr.io/mattrobenolt/ps-http-sim image is a shell-less scratch
# image, so it can't read env vars in a start command. We copy its static Go
# binary onto alpine (which has /bin/sh) and pass the MySQL connection from
# Railway service variables at runtime.
FROM alpine:3.20
COPY --from=ghcr.io/mattrobenolt/ps-http-sim:latest /ps-http-sim /usr/local/bin/ps-http-sim
EXPOSE 3900
ENTRYPOINT ["/bin/sh","-c","exec /usr/local/bin/ps-http-sim -listen-port=3900 -mysql-addr=\"$MYSQLHOST\" -mysql-port=\"$MYSQLPORT\" -mysql-dbname=\"$MYSQLDATABASE\" -mysql-user=\"$MYSQLUSER\" -mysql-pass=\"$MYSQLPASSWORD\""]
