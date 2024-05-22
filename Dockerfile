FROM rust:latest as rust
LABEL org.opencontainers.image.source=https://github.com/dylibso/wasmstore
LABEL org.opencontainers.image.description="Wasmstore image"
LABEL org.opencontainers.image.licenses=BSD-3-Clause

FROM ocaml/opam:debian-12-ocaml-5.1 as build
RUN sudo apt-get update && sudo apt-get install -y libgmp-dev pkg-config libssl-dev libffi-dev curl
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
COPY --chown=opam . /home/opam/src
COPY --chown=opam --from=rust /usr/local/cargo /home/opam/.cargo
COPY --chown=opam --from=rust /usr/local/cargo/bin/rustc /usr/local/bin/rustc
RUN sudo ln -sf /home/opam/.cargo/bin/cargo /usr/bin/cargo
RUN sudo ln -sf /home/opam/.cargo/bin/rustc /usr/bin/rustc
WORKDIR /home/opam/src
RUN opam repository add opam-repository git+https://github.com/ocaml/opam-repository.git
RUN opam update -y
RUN opam install -j 1 dune -y
RUN opam install -j $(nproc) opam-monorepo -y
RUN opam repository add dune-universe git+https://github.com/dune-universe/opam-overlays.git
RUN opam monorepo pull
RUN eval $(opam env) && dune build -j $(nproc) ./bin/main.exe

FROM debian:12
ENV PORT=6384
ENV HOST=0.0.0.0
COPY --from=build /usr/lib /usr/lib
COPY --from=build /home/opam/src/_build/default/bin/main.exe /usr/bin/wasmstore
RUN groupadd -r wasmstore && useradd -m -r -g wasmstore wasmstore
USER wasmstore
WORKDIR /home/wasmstore
EXPOSE ${PORT}
RUN mkdir -p /home/wasmstore/db
CMD wasmstore server --root /home/wasmstore/db --host ${HOST} --port ${PORT}
