use anyhow::{Context, Result};
use lexpr::Value;
use std::io::{BufRead, Write};
use std::os::unix::net::UnixStream;

pub fn send_sexp(stream: &mut UnixStream, val: &Value) -> Result<()> {
    let sexp_str = lexpr::to_string(val).context("Failed to serialize S-expression")?;
    stream.write_all(sexp_str.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    Ok(())
}

/// Guile's writer emits selected characters as `\xHH` inside strings, while
/// `lexpr` implements the R7RS `\xHEX;` spelling.  Normalize only unescaped
/// hexadecimal escapes inside strings; a literal `\\x...` remains untouched.
fn normalize_guile_string_escapes(input: &str) -> Result<String> {
    let chars: Vec<char> = input.chars().collect();
    let mut output = String::with_capacity(input.len());
    let mut in_string = false;
    let mut index = 0;

    while index < chars.len() {
        let ch = chars[index];
        if ch == '"' {
            in_string = !in_string;
            output.push(ch);
            index += 1;
        } else if in_string && ch == '\\' {
            if index + 1 < chars.len() && chars[index + 1] == '\\' {
                output.push('\\');
                output.push('\\');
                index += 2;
            } else if index + 3 < chars.len() && chars[index + 1] == 'x' {
                let start = index + 2;
                let end = start + 2;
                if !chars[start..end].iter().all(|ch| ch.is_ascii_hexdigit()) {
                    anyhow::bail!("Guile hexadecimal escape must contain two digits");
                }
                let digits: String = chars[start..end].iter().collect();
                let codepoint =
                    u32::from_str_radix(&digits, 16).context("Invalid Guile hexadecimal escape")?;
                let decoded = char::from_u32(codepoint)
                    .ok_or_else(|| anyhow::anyhow!("Invalid Unicode codepoint: {digits}"))?;
                output.push(decoded);
                index = end;
            } else {
                output.push(ch);
                if index + 1 < chars.len() {
                    output.push(chars[index + 1]);
                    index += 2;
                } else {
                    index += 1;
                }
            }
        } else {
            output.push(ch);
            index += 1;
        }
    }
    Ok(output)
}

pub fn receive_event<R: BufRead>(reader: &mut R) -> Result<Option<Value>> {
    loop {
        let mut line = String::new();
        let n = reader
            .read_line(&mut line)
            .context("Failed to read from socket")?;
        if n == 0 {
            return Ok(None);
        }

        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        // The socket protocol is newline framed: both Guile `write` and
        // send_sexp escape embedded newlines.  A parse failure after one frame
        // is therefore malformed input, never a reason to wait indefinitely.
        let normalized = normalize_guile_string_escapes(trimmed)?;
        let value = lexpr::from_str(&normalized)
            .with_context(|| format!("Failed to parse S-expression frame: {line}"))?;
        return Ok(Some(value));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn receives_guile_hex_escape_without_waiting_for_more_input() {
        let input = b"(cognitive-state ((content . \"wartosc\\xa0face\")))\n";
        let mut reader = Cursor::new(input);

        let value = receive_event(&mut reader).unwrap().unwrap();
        assert!(value.to_string().contains("wartosc\u{a0}face"));
    }

    #[test]
    fn rejects_a_malformed_complete_frame_instead_of_hanging() {
        let mut reader = Cursor::new(b"(cognitive-state (broken)\n");

        let error = receive_event(&mut reader).unwrap_err().to_string();
        assert!(error.contains("Failed to parse S-expression frame"));
    }
}
