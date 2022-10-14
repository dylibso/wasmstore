FROM ocaml/opam:latest as build
COPY . .
RUN sudo apt-get install -y libev-dev libgmp-dev pkg-config libssl-dev
RUN opam install --deps-only .
RUN opam exec -- dune build
RUN sudo cp _build/install/default/bin/wasmstore /usr/bin/wasmstore

FROM ocaml/opam:latest
ENV PORT=6384
ENV HOST=127.0.0.1
COPY --from=build /usr/lib /usr/lib
COPY --from=build /usr/bin /usr/bin
RUN sudo groupadd -r wasmstore && sudo useradd -m -r -g wasmstore wasmstore
USER wasmstore
WORKDIR /home/wasmstore
EXPOSE ${PORT}
CMD wasmstore server --root /home/wasmstore/db --host ${HOST} --port ${PORT}
