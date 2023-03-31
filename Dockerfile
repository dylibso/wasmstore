FROM rust:latest as rust

FROM ocaml/opam:latest as build
RUN sudo apt-get install -y libev-dev libgmp-dev pkg-config libssl-dev libffi-dev curl
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
COPY --chown=opam . ./src
COPY --chown=opam --from=rust /usr/local/cargo /home/opam/.cargo
COPY --chown=opam --from=rust /usr/local/cargo/bin/rustc /usr/local/bin/rustc
RUN sudo ln -sf /home/opam/.cargo/bin/cargo /usr/bin/cargo
RUN sudo ln -sf /home/opam/.cargo/bin/rustc /usr/bin/rustc
WORKDIR /home/opam/src
RUN opam install . --deps-only -y
RUN eval $(opam env) && dune build

FROM ocaml/opam:latest
ENV PORT=6384
ENV HOST=0.0.0.0
COPY --from=build /usr/lib /usr/lib
COPY --from=build /home/opam/src/_build/install/default/bin/wasmstore /usr/bin/wasmstore
RUN sudo groupadd -r wasmstore && sudo useradd -m -r -g wasmstore wasmstore
USER wasmstore
WORKDIR /home/wasmstore
EXPOSE ${PORT}
RUN mkdir -p /home/wasmstore/db
CMD wasmstore server --root /home/wasmstore/db --host ${HOST} --port ${PORT}
