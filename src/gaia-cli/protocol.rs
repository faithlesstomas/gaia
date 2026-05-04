use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use anyhow::{Context, Result};
use lexpr::Value;

pub fn send_sexp(stream: &mut UnixStream, val: &Value) -> Result<()> {
    let sexp_str = lexpr::to_string(val).context("Failed to serialize S-expression")?;
    stream.write_all(sexp_str.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    Ok(())
}

pub fn receive_event(reader: &mut BufReader<UnixStream>) -> Result<Option<Value>> {
    let mut line = String::new();
    let n = reader.read_line(&mut line).context("Failed to read from socket")?;
    if n == 0 {
        return Ok(None);
    }
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let val = lexpr::from_str(trimmed).context(format!("Failed to parse S-expression: {}", trimmed))?;
    Ok(Some(val))
}
