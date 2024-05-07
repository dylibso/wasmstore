use std::io::Read;
use wasmparser::{Chunk, Parser, Payload::*, Validator, WasmFeatures};

fn err<T: ToString>(x: T) -> String {
    x.to_string()
}

fn validate(mut reader: impl Read) -> Result<(), String> {
    let mut buf = Vec::new();
    let mut parser = Parser::new(0);
    let mut eof = false;
    let mut stack = Vec::new();
    let mut validator = Validator::new_with_features(wasmparser::WasmFeatures::all());

    loop {
        let (payload, consumed) = match parser
            .parse(&buf, eof)
            .map_err(|x| x.message().to_string())?
        {
            Chunk::NeedMoreData(hint) => {
                if eof {
                    return Err("unexpected end-of-file".to_string());
                }

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

        match &payload {
            ModuleSection { parser: p, .. } | ComponentSection { parser: p, .. } => {
                stack.push(parser.clone());
                parser = p.clone();
            }
            _ => (),
        }

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

fn return_string(mut s: String) -> *mut u8 {
    s.push('\0');
    s.shrink_to_fit();
    let ptr = s.as_ptr();
    std::mem::forget(s);
    ptr as *mut _
}

#[no_mangle]
pub unsafe fn wasm_error_free(s: *mut u8) {
    let len = std::ffi::CStr::from_ptr(s as *const _).to_bytes().len() + 1;
    let s = String::from_raw_parts(s, len, len);
    drop(s)
}

#[no_mangle]
pub unsafe fn wasm_verify_file(filename: *const u8, len: usize) -> *mut u8 {
    let slice = std::slice::from_raw_parts(filename, len);
    if let Ok(s) = std::str::from_utf8(slice) {
        let file = match std::fs::File::open(s) {
            Ok(f) => f,
            Err(_) => return return_string(format!("unable to open file {}", s)),
        };

        match validate(file) {
            Ok(()) => std::ptr::null_mut(),
            Err(e) => return_string(e),
        }
    } else {
        std::ptr::null_mut()
    }
}

#[no_mangle]
pub unsafe fn wasm_verify_string(filename: *const u8, len: usize) -> *mut u8 {
    let slice = std::slice::from_raw_parts(filename, len);
    match validate(slice) {
        Ok(()) => std::ptr::null_mut(),
        Err(s) => return_string(s),
    }
}
