use anyhow::{Context, Result};
use lexpr::Value;
use std::io::{BufReader, Write};
use std::os::unix::net::UnixStream;

pub fn send_sexp(stream: &mut UnixStream, val: &Value) -> Result<()> {
    let sexp_str = lexpr::to_string(val).context("Failed to serialize S-expression")?;
    stream.write_all(sexp_str.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    Ok(())
}

pub fn receive_event(reader: &mut BufReader<UnixStream>) -> Result<Option<Value>> {
    let mut buffer = String::new();
    loop {
        let mut line = String::new();
        let n = std::io::BufRead::read_line(reader, &mut line).context("Failed to read from socket")?;
        if n == 0 {
            if buffer.trim().is_empty() {
                return Ok(None);
            } else {
                return Err(anyhow::anyhow!("Unexpected EOF while parsing S-expression: {}", buffer));
            }
        }
        buffer.push_str(&line);
        
        let trimmed = buffer.trim();
        if trimmed.is_empty() {
            continue;
        }
        
        // Use Parser to check if we have a complete S-expression
        let mut parser = lexpr::Parser::from_str(trimmed);
        match parser.next_value() {
            Ok(Some(val)) => return Ok(Some(val)),
            Ok(None) => continue, // Need more data
            Err(e) => {
                // Check if the error is "premature EOF" which means we need more data
                let err_str = e.to_string();
                if err_str.contains("EOF") || err_str.contains("expected") || err_str.contains("unclosed") {
                    continue;
                } else {
                    return Err(anyhow::anyhow!("Failed to parse S-expression: {}\nBuffer: {}", e, buffer));
                }
            }
        }
    }
}
