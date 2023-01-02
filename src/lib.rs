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

#[no_mangle]
unsafe extern "C" fn wasmstore_error_free(err: *mut std::ffi::c_char) {
    drop(std::ffi::CString::from_raw(err))
}

#[no_mangle]
unsafe extern "C" fn wasmstore_verify_string(s: *const u8, len: usize) -> *mut std::ffi::c_char {
    let buf = std::slice::from_raw_parts(s, len);
    match validate(buf) {
        Ok(()) => std::ptr::null_mut(),
        Err(s) => std::ffi::CString::new(s).unwrap_or_default().into_raw(),
    }
}

#[no_mangle]
unsafe extern "C" fn wasmstore_verify_file(s: *const std::ffi::c_char) -> *mut std::ffi::c_char {
    let filename = std::ffi::CStr::from_ptr(s).to_string_lossy();
    let file = match std::fs::File::open(filename.as_ref()) {
        Ok(f) => f,
        Err(e) => {
            return std::ffi::CString::new(e.to_string())
                .unwrap_or_default()
                .into_raw()
        }
    };
    match validate(file) {
        Ok(()) => std::ptr::null_mut(),
        Err(s) => std::ffi::CString::new(s).unwrap_or_default().into_raw(),
    }
}
