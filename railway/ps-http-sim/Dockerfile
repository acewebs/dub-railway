# Wrapper image for ps-http-sim on Railway.
# The upstream ghcr.io/mattrobenolt/ps-http-sim image is a shell-less scratch
# image, so it can't read env vars in a start command. We copy its static Go
# binary onto alpine (which has /bin/sh) and pass the MySQL connection from
# Railway service variables at runtime.
FROM alpine:3.20
COPY --from=ghcr.io/mattrobenolt/ps-http-sim:latest /ps-http-sim /usr/local/bin/ps-http-sim
EXPOSE 3900
# ps-http-sim has no -mysql-user/-pass flags: it uses the credentials from the
# incoming PlanetScale request (the web app's PLANETSCALE_DATABASE_URL user:pass).
# Binds 0.0.0.0 (it can't bind :: — panics on address formatting); reachable on
# Railway's private network in environments created after 2025-10-16.
ENTRYPOINT ["/bin/sh","-c","exec /usr/local/bin/ps-http-sim -listen-addr=0.0.0.0 -listen-port=3900 -mysql-addr=\"$MYSQLHOST\" -mysql-port=\"$MYSQLPORT\" -mysql-dbname=\"$MYSQLDATABASE\""]
