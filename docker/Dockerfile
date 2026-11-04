# Hackmode actor service image.
#
# Built from the repository root (source is shipped to the build host with
# git archive, like the rest of the actor fleet):
#   docker build -f docker/Dockerfile -t starintel/hackmode-actor-service:<rev> .
#
# Build stage mirrors CI (.github/workflows/core.yml): Ubuntu SBCL, a fresh
# Quicklisp, and the pinned dependency checkouts. Runtime is a slim image
# with the saved executable, the ontology spec tree, and the C libraries the
# executable loads at runtime.

FROM ubuntu:24.04 AS build

ARG TEK9_REV=e6d1cb86a2e268a894eae3acae9617238b2adcff
ARG STAR_CL_REV=b8dfbe2f9f56065ace8c3313b92ca748a115cdfa
ARG STAR_LANG_REV=09f3b6dab15a9bcb9b5dd7866735d65301571211
ARG SENTO_REV=6a510c5b58469e72e6363bd3a6059d80b9a5c320
ARG CMS_ULID_REV=fff84302dee5db42fb90aafd834af3ffbfd6c2bb

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      sbcl curl git ca-certificates build-essential \
      liblmdb-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/opt/hackmode
RUN mkdir -p /build/deps /out /opt/hackmode && cd /build/deps \
    && git clone --quiet --filter=blob:none https://github.com/lost-rob0t/tek9.git tek9 \
    && git -C tek9 fetch --depth=1 origin "$TEK9_REV" && git -C tek9 checkout --quiet --detach "$TEK9_REV" \
    && git clone --quiet --filter=blob:none https://github.com/lost-rob0t/star-cl.git star-cl \
    && git -C star-cl fetch --depth=1 origin "$STAR_CL_REV" && git -C star-cl checkout --quiet --detach "$STAR_CL_REV" \
    && git clone --quiet --filter=blob:none https://github.com/lost-rob0t/star-lang.git star-lang \
    && git -C star-lang fetch --depth=1 origin "$STAR_LANG_REV" && git -C star-lang checkout --quiet --detach "$STAR_LANG_REV" \
    && git clone --quiet --filter=blob:none https://github.com/mdbergmann/cl-gserver.git sento \
    && git -C sento fetch --depth=1 origin "$SENTO_REV" && git -C sento checkout --quiet --detach "$SENTO_REV" \
    && git clone --quiet --filter=blob:none https://gitlab.com/colinstrickland/cms-ulid.git cms-ulid \
    && git -C cms-ulid fetch --depth=1 origin "$CMS_ULID_REV" && git -C cms-ulid checkout --quiet --detach "$CMS_ULID_REV"

RUN curl -sS --retry 5 -o /tmp/quicklisp.lisp https://beta.quicklisp.org/quicklisp.lisp \
    && sbcl --non-interactive \
         --load /tmp/quicklisp.lisp \
         --eval '(quicklisp-quickstart:install :path "/opt/hackmode/quicklisp")'

COPY . /build/hackmode

ENV CL_SOURCE_REGISTRY=/build/deps/star-lang//
WORKDIR /build/hackmode
RUN sbcl --non-interactive \
      --load /opt/hackmode/quicklisp/setup.lisp \
      --eval '(push (truename "/build/deps/cms-ulid/") asdf:*central-registry*)' \
      --eval '(push (truename "/build/deps/sento/") asdf:*central-registry*)' \
      --eval '(asdf:load-asd (truename "/build/deps/tek9/src/tek9.asd"))' \
      --eval '(asdf:load-asd (truename "/build/deps/star-cl/src/starintel.asd"))' \
      --eval '(asdf:load-asd (truename "/build/deps/sento/sento.asd"))' \
      --eval '(asdf:load-asd (truename "source/hackmode-core/hackmode.asd"))' \
      --eval '(asdf:load-asd (truename "source/hackmode-database/hackmode-database.asd"))' \
      --eval '(asdf:load-asd (truename "source/hackmode-actors/hackmode-actors.asd"))' \
      --eval '(ql:quickload :hackmode-actors)' \
      --eval '(sb-ext:save-lisp-and-die "/out/hackmode-actor-service" :toplevel (function hackmode-actors:hackmode-actor-service-main) :executable t :compression t)'

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      liblmdb0 libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --no-create-home --system hackmode

COPY --from=build /out/hackmode-actor-service /bin/hackmode-actor-service
COPY --from=build /opt/hackmode/.cache /opt/hackmode/.cache
COPY spec /opt/hackmode/spec
COPY docker/hackmode-actor-entrypoint.sh /bin/hackmode-actor-entrypoint

ENV HOME=/tmp \
    HACKMODE_DB_PATH=/var/lib/hackmode/operation \
    HACKMODE_ONTOLOGY_SPEC_DIR=/opt/hackmode/spec \
    STARINTEL_SERVICE_HEALTH_FILE=/tmp/hackmode-actor-health

RUN mkdir -p /var/lib/hackmode && chown -R 10001:10001 /var/lib/hackmode \
    && chmod +x /bin/hackmode-actor-entrypoint \
    && chmod -R a+rX /opt/hackmode/.cache
VOLUME ["/var/lib/hackmode"]
USER hackmode
WORKDIR /tmp

ENTRYPOINT ["/bin/hackmode-actor-entrypoint"]
