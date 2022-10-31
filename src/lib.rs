use std::io::Read;

const BUF_SIZE: usize = 4096 * 2;

#[ocaml::func]
#[ocaml::sig("string -> (unit, string) result")]
pub unsafe fn wasm_verify_file(filename: &str) -> Result<(), String> {
    let mut f = match std::fs::File::open(filename) {
        Ok(f) => f,
        Err(_) => return Err(format!("unable to open file: {}", filename)),
    };

    let mut parser = wasmparser::Parser::new(0);
    let mut validator = wasmparser::Validator::new();

    let mut buf = [0u8; BUF_SIZE];

    while let Ok(n) = f.read(&mut buf) {
        if n == 0 {
            break;
        }
        let mut index = 0;
        while index < n {
            let res = parser
                .parse(&buf[index..n], n < BUF_SIZE)
                .map_err(|e| e.to_string())?;
            match res {
                wasmparser::Chunk::NeedMoreData(_) => {
                    if n < BUF_SIZE {
                        break;
                    } else {
                        continue;
                    }
                }
                wasmparser::Chunk::Parsed { payload, consumed } => {
                    index += consumed;
                    match validator.payload(&payload).map_err(|e| e.to_string())? {
                        wasmparser::ValidPayload::End(_) | wasmparser::ValidPayload::Ok => {
                            return Ok(());
                        }
                        wasmparser::ValidPayload::Parser(p) => {
                            parser = p;
                        }
                        _ => (),
                    }
                }
            }
        }
    }

    let res = parser.parse(&[], true).map_err(|e| e.to_string())?;
    match res {
        wasmparser::Chunk::Parsed { payload, .. } => {
            match validator.payload(&payload).map_err(|e| e.to_string())? {
                wasmparser::ValidPayload::End(_) | wasmparser::ValidPayload::Ok => {
                    return Ok(());
                }
                _ => (),
            }
        }
        _ => (),
    }

    return Err("unable to detect end of module".to_string());
}

#[ocaml::func]
#[ocaml::sig("string -> (unit, string) result")]
pub unsafe fn wasm_verify_string(data: &[u8]) -> Result<(), String> {
    let parser = wasmparser::Parser::new(0);
    let mut validator = wasmparser::Validator::new();

    for payload in parser.parse_all(data) {
        let payload = payload.map_err(|x| x.to_string())?;
        match validator.payload(&payload).map_err(|e| e.to_string())? {
            wasmparser::ValidPayload::Ok | wasmparser::ValidPayload::End(_) => return Ok(()),
            _ => (),
        }
    }

    return Err("unable to detect end of module".to_string());
}
