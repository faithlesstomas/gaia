// GAIA CLI — Scrollback REPL Client (Phase 1)
//
// Connects to the GAIA Headless Engine via UNIX socket.
// Uses rustyline for line editing with history (arrow keys).
// Prints server events as colored terminal output (scrollback).

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use anyhow::Result;
use lexpr::Value;
use rustyline::error::ReadlineError;
use rustyline::history::DefaultHistory;
use rustyline::{Config, EditMode, Editor};

// ANSI escape codes
const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const RED: &str = "\x1b[31m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const CYAN: &str = "\x1b[36m";
const GREY: &str = "\x1b[90m";

const SOCKET_PATH: &str = "/tmp/gaia.sock";

fn main() -> Result<()> {
    println!("\n{BOLD}{GREEN}GAIA CLI v0.2.0{RESET}");
    println!("Type {BOLD}/help{RESET} for commands or enter a task.\n");

    let mut stream = connect_with_retry(SOCKET_PATH)?;
    let mut reader = BufReader::new(stream.try_clone()?);

    let config = Config::builder()
        .edit_mode(EditMode::Emacs)
        .auto_add_history(false)
        .build();
    let mut editor = Editor::<(), DefaultHistory>::with_config(config)?;

    loop {
        let prompt = format!("{BOLD}{GREEN}(GAIA) >{RESET} ");
        match editor.readline(&prompt) {
            Ok(line) => {
                let trimmed = line.trim().to_string();
                if trimmed.is_empty() {
                    continue;
                }

                let _ = editor.add_history_entry(&trimmed);

                match dispatch(&trimmed, &mut stream, &mut reader) {
                    Ok(Action::Continue) => {}
                    Ok(Action::Exit) => break,
                    Err(e) => {
                        eprintln!("{RED}[Connection lost] {e}{RESET}");
                        match connect_with_retry(SOCKET_PATH) {
                            Ok(new_stream) => {
                                reader = BufReader::new(new_stream.try_clone()?);
                                stream = new_stream;
                            }
                            Err(re) => {
                                eprintln!("{RED}[Fatal] Cannot reconnect: {re}{RESET}");
                                break;
                            }
                        }
                    }
                }
            }
            Err(ReadlineError::Interrupted) => {
                println!("{YELLOW}^C (Use /exit to quit){RESET}");
            }
            Err(ReadlineError::Eof) => break,
            Err(e) => {
                eprintln!("{RED}Readline error: {e}{RESET}");
                break;
            }
        }
    }

    println!("Bye.");
    Ok(())
}

enum Action {
    Continue,
    Exit,
}

fn dispatch(
    input: &str,
    stream: &mut UnixStream,
    reader: &mut BufReader<UnixStream>,
) -> Result<Action> {
    match input {
        "/exit" | "/quit" => Ok(Action::Exit),
        "/help" => {
            print_help();
            Ok(Action::Continue)
        }
        "/clear" => {
            send_sexp(stream, &Value::list(vec![Value::symbol("clear")]))?;
            receive_events(reader)?;
            Ok(Action::Continue)
        }
        "/env" => {
            send_sexp(stream, &Value::list(vec![Value::symbol("env")]))?;
            receive_events(reader)?;
            Ok(Action::Continue)
        }
        "/model" => {
            send_sexp(stream, &Value::list(vec![Value::symbol("get-model")]))?;
            receive_events(reader)?;
            Ok(Action::Continue)
        }
        _ if input.starts_with("/eval ") => {
            let code = &input[6..];
            let cmd = Value::list(vec![Value::symbol("repl"), Value::string(code)]);
            send_sexp(stream, &cmd)?;
            receive_events(reader)?;
            Ok(Action::Continue)
        }
        _ if input.starts_with("/model ") => {
            let model = &input[7..];
            let cmd = Value::list(vec![
                Value::symbol("set-model"),
                Value::string(model),
            ]);
            send_sexp(stream, &cmd)?;
            receive_events(reader)?;
            Ok(Action::Continue)
        }
        _ if input.starts_with("/ask ") => {
            let query = &input[5..];
            let cmd = Value::list(vec![Value::symbol("ask"), Value::string(query)]);
            send_sexp(stream, &cmd)?;
            receive_events(reader)?;
            Ok(Action::Continue)
        }
        _ if input.starts_with('/') => {
            eprintln!(
                "{YELLOW}Unknown command: {input}. Type /help for available commands.{RESET}"
            );
            Ok(Action::Continue)
        }
        _ => {
            // Standard RLM evaluation
            let cmd = Value::list(vec![Value::symbol("eval"), Value::string(input)]);
            send_sexp(stream, &cmd)?;
            receive_events(reader)?;
            Ok(Action::Continue)
        }
    }
}

fn send_sexp(stream: &mut UnixStream, sexp: &Value) -> Result<()> {
    let s = lexpr::to_string(sexp)?;
    writeln!(stream, "{}", s)?;
    stream.flush()?;
    Ok(())
}

/// Reads and prints server events until a terminal event (final/error/info/env-list)
/// is received, then returns control to the REPL prompt.
fn receive_events(reader: &mut BufReader<UnixStream>) -> Result<()> {
    let mut line = String::new();
    loop {
        line.clear();
        let n = reader.read_line(&mut line)?;
        if n == 0 {
            return Err(anyhow::anyhow!("Server disconnected"));
        }

        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        match lexpr::from_str(trimmed) {
            Ok(Value::Cons(cons)) => {
                let tag = cons.car().as_symbol().unwrap_or("unknown");
                let content = if let Value::Cons(cdr) = cons.cdr() {
                    cdr.car().as_str().unwrap_or("").to_string()
                } else {
                    String::new()
                };

                match tag {
                    "status" => {
                        // Overwrite-style status (dim, on stderr so it doesn't pollute output)
                        eprint!("\r{DIM}{GREY}⠋ {content}{RESET}\x1b[K");
                    }
                    "thought" => {
                        if !content.is_empty() {
                            println!("{GREY}{}{RESET}", content);
                        }
                    }
                    "code" => {
                        eprintln!(); // Clear status line
                        println!("{BOLD}{CYAN}╭─ scheme{RESET}");
                        for code_line in content.lines() {
                            println!("{CYAN}│{RESET} {code_line}");
                        }
                        println!("{BOLD}{CYAN}╰─{RESET}");
                    }
                    "result" => {
                        println!("{GREEN}✔ Result:{RESET} {content}");
                    }
                    "repl-error" => {
                        // Non-fatal REPL error: show it but CONTINUE listening for more events
                        eprintln!(); // Clear status line
                        eprintln!("{RED}✘ REPL Error:{RESET} {content}");
                    }
                    "final" => {
                        eprintln!(); // Clear status line
                        println!("\n{BOLD}Final Answer:{RESET} {content}\n");
                        return Ok(());
                    }
                    "error" => {
                        // Fatal Engine Error: show it and RETURN to prompt
                        eprintln!(); // Clear status line
                        eprintln!("{RED}✘ Engine Error:{RESET} {content}");
                        return Ok(());
                    }
                    "info" => {
                        println!("{CYAN}{content}{RESET}");
                        return Ok(());
                    }
                    "env-list" => {
                        println!("{BOLD}REPL Bindings:{RESET}");
                        // Parse the alist from the second element
                        if let Value::Cons(cdr) = cons.cdr() {
                            print_env_bindings(cdr.car());
                        }
                        return Ok(());
                    }
                    "model-info" => {
                        println!("{BOLD}Current model:{RESET} {content}");
                        return Ok(());
                    }
                    _ => {
                        println!("[{tag}] {content}");
                    }
                }
            }
            Ok(other) => {
                println!("{other}");
            }
            Err(_) => {
                println!("{trimmed}");
            }
        }
    }
}

fn print_env_bindings(val: &Value) {
    match val {
        Value::Null => {
            println!("  {DIM}(empty){RESET}");
        }
        Value::Cons(cons) => {
            // Walk the alist
            let mut current = Value::Cons(cons.clone());
            while let Value::Cons(pair) = &current {
                let entry = pair.car();
                if let Value::Cons(kv) = entry {
                    let key = kv.car();
                    let val = kv.cdr();
                    println!("  {CYAN}{key}{RESET} = {val}");
                }
                current = pair.cdr().clone();
            }
        }
        _ => {
            println!("  {val}");
        }
    }
}

fn connect_with_retry(path: &str) -> Result<UnixStream> {
    for attempt in 1..=10 {
        match UnixStream::connect(path) {
            Ok(stream) => {
                println!("{GREEN}[Connected to GAIA Engine]{RESET}");
                return Ok(stream);
            }
            Err(_e) if attempt < 10 => {
                eprintln!(
                    "{YELLOW}[Waiting for server on {path}... (attempt {attempt}/10)]{RESET}"
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

fn print_help() {
    println!("{BOLD}Available commands:{RESET}");
    println!("  {CYAN}/help{RESET}              Show this help");
    println!("  {CYAN}/eval <scheme>{RESET}     Execute Scheme code directly in REPL");
    println!("  {CYAN}/env{RESET}               Show REPL environment bindings");
    println!("  {CYAN}/clear{RESET}             Clear conversation history and REPL env");
    println!("  {CYAN}/ask <query>{RESET}       One-shot question to AI (no RLM loop)");
    println!("  {CYAN}/model{RESET}             Show current model");
    println!("  {CYAN}/model <name>{RESET}      Switch to a different model");
    println!("  {CYAN}/exit{RESET}              Quit GAIA CLI");
    println!();
    println!("  {DIM}<query>{RESET}             Start standard RLM investigation");
}
