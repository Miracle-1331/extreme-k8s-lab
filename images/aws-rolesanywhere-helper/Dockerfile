FROM alpine:3.20

ARG TARGETARCH
ARG HELPER_VERSION=1.7.3

RUN apk add --no-cache ca-certificates curl && \
    case "${TARGETARCH}" in \
    amd64) HELPER_ARCH="X86_64" ;; \
    arm64) HELPER_ARCH="Aarch64" ;; \
    *) echo "unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    HELPER_URL="https://rolesanywhere.amazonaws.com/releases/${HELPER_VERSION}/${HELPER_ARCH}/Linux/Amzn2023/aws_signing_helper" && \
    echo "Downloading ${HELPER_URL}" && \
    curl -fsSL "${HELPER_URL}" -o /usr/local/bin/aws_signing_helper && \
    chmod 0555 /usr/local/bin/aws_signing_helper && \
    /usr/local/bin/aws_signing_helper version || true

USER 65532:65532

ENTRYPOINT ["/usr/local/bin/aws_signing_helper"]