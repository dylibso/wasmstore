pub fn main() -> std::io::Result<()> {
    ocaml_build::Sigs::new("src/rust.ml").generate()?;
    let _ = std::process::Command::new("dune")
        .args(&["build", "@fmt", "--auto-promote"])
        .status();
    Ok(())
}
