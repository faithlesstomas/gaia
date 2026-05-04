use std::os::unix::net::UnixStream;
use std::time::Duration;
use anyhow::Result;

pub const SOCKET_PATH: &str = "/tmp/gaia.sock";

pub fn connect_with_retry(path: &str) -> Result<UnixStream> {
    for attempt in 1..=10 {
        match UnixStream::connect(path) {
            Ok(stream) => {
                eprintln!("\x1b[32m[Connected to GAIA Engine]\x1b[0m");
                return Ok(stream);
            }
            Err(_e) if attempt < 10 => {
                eprintln!(
                    "\x1b[33m[Waiting for server on {}... (attempt {}/10)]\x1b[0m",
                    path, attempt
                );
                std::thread::sleep(Duration::from_secs(2));
            }
            Err(e) => {
                return Err(anyhow::anyhow!(
                    "Failed to connect to {}: {}",
                    path,
                    e
                ));
            }
        }
    }
    unreachable!()
}
