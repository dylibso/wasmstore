use std::io::Read;
use wasmparser::{Chunk, Parser, Validator};

fn err<T: ToString>(x: T) -> String {
    x.to_string()
}

fn validate(mut reader: impl Read) -> Result<(), String> {
    let mut buf = Vec::new();
    let mut parser = Parser::new(0);
    let mut eof = false;
    let mut stack = Vec::new();
    let mut validator = Validator::new();

    loop {
        let (payload, consumed) = match parser.parse(&buf, eof).map_err(err)? {
            Chunk::NeedMoreData(hint) => {
                assert!(!eof); // otherwise an error would be returned

                // Use the hint to preallocate more space, then read
                // some more data into our buffer.
                //
                // Note that the buffer management here is not ideal,
                // but it's compact enough to fit in an example!
                let len = buf.len();
                buf.extend((0..hint).map(|_| 0u8));
                let n = reader.read(&mut buf[len..]).map_err(err)?;
                buf.truncate(len + n);
                eof = n == 0;
                continue;
            }

            Chunk::Parsed { consumed, payload } => (payload, consumed),
        };

        match validator.payload(&payload).map_err(err)? {
            wasmparser::ValidPayload::End(_) => {
                if let Some(parent_parser) = stack.pop() {
                    parser = parent_parser;
                } else {
                    break;
                }
            }
            _ => (),
        }

        // once we're done processing the payload we can forget the
        // original.
        buf.drain(..consumed);
    }

    Ok(())
}

#[ocaml::func]
#[ocaml::sig("string -> string option")]
pub unsafe fn wasm_verify_file(filename: &str) -> Option<String> {
    let file = match std::fs::File::open(filename) {
        Ok(f) => f,
        Err(_) => return Some(format!("unable to open file {}", filename)),
    };

    match validate(file) {
        Ok(()) => None,
        Err(s) => return Some(s),
    }
}

#[ocaml::func]
#[ocaml::sig("string -> string option")]
pub unsafe fn wasm_verify_string(data: &[u8]) -> Option<String> {
    match validate(data) {
        Ok(()) => None,
        Err(s) => return Some(s),
    }
}
