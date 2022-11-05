#[ocaml::func]
#[ocaml::sig("string -> (unit, string) result")]
pub unsafe fn wasm_verify_file(filename: &str) -> Result<(), String> {
    let data = match std::fs::read(filename) {
        Ok(f) => f,
        Err(_) => return Err(format!("unable to open file {}", filename)),
    };

    let mut validator = wasmparser::Validator::new();

    match validator.validate_all(&data) {
        Ok(_) => Ok(()),
        Err(e) => return Err(format!("{} (at offset 0x{:x})", e.message(), e.offset())),
    }
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
