# ----------------------------------------
# Builder
#
# Creates the registry binary.
FROM base/golang:1.8 AS builder

ENV TRAEFIK_VERSION=${version}

# Set environment variables.
ENV DISTRIBUTION_DIR=/go/src/github.com/containous/traefik

# Install dependencies.
RUN apk add --no-cache \
    ca-certificates \
 && apk add --no-cache --virtual .build-deps \
    bash \
    gcc \
    g++ \
    make \
    git

# Set the working directory to the distribution directory.
WORKDIR $DISTRIBUTION_DIR

# Clone the git repo into the container.
RUN git clone https://github.com/containous/traefik . \
 && git checkout tags/v$TRAEFIK_VERSION \
 && mkdir "dist"

# Build the registry binary.
RUN ["/bin/bash", "-c", "./script/make.sh generate binary"]

# ----------------------------------------
# Traefik
#
# Creates the traefik image using the binary from the builder.
FROM ${base_image}

# Install dependencies.
RUN apk add --no-cache \
    ca-certificates

COPY --from=builder /go/bin/traefik /usr/local/bin/

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80

CMD ["--help"]
