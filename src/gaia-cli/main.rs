use anyhow::Result;
use lexpr::Value;
use rustyline::error::ReadlineError;
use rustyline::DefaultEditor;
use std::io::BufReader;
use std::os::unix::net::UnixStream;

mod connection;
mod protocol;
mod render;

use crate::connection::{connect_with_retry, SOCKET_PATH};
use crate::protocol::send_sexp;
use crate::render::*;

enum Action {
    Continue,
    Exit,
}

fn main() -> Result<()> {
    println!("\n{BOLD}{GREEN}GAIA CLI v0.2.0{RESET}");
    println!("Type {BOLD}/help{RESET} for commands or enter a task.\n");

    // Default to a new session ID on startup as requested
    let mut session_id = format!(
        "gaia-cli-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs()
    );

    let mut stream = connect_with_retry(SOCKET_PATH)?;
    send_sexp(
        &mut stream,
        &Value::list(vec![
            Value::symbol("session"),
            Value::string(session_id.clone()),
        ]),
    )?;

    let mut reader = BufReader::new(stream.try_clone()?);
    let mut rl = DefaultEditor::new()?;

    loop {
        let prompt = format!("{}(GAIA) > {}", GREEN, RESET);
        let readline = rl.readline(&prompt);

        match readline {
            Ok(line) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                let _ = rl.add_history_entry(trimmed);

                match dispatch(trimmed, &mut stream, &mut reader, &mut session_id) {
                    Ok(Action::Exit) => break,
                    Ok(Action::Continue) => {}
                    Err(e) => {
                        print_error(&format!("Error: {}", e));
                        // Attempt to reconnect if stream is broken
                        if e.to_string().contains("Broken pipe") || e.to_string().contains("connection") {
                            match connect_with_retry(SOCKET_PATH) {
                                Ok(new_stream) => {
                                    stream = new_stream;
                                    reader = BufReader::new(stream.try_clone()?);
                                    // Re-establish session
                                    send_sexp(&mut stream, &Value::list(vec![Value::symbol("session"), Value::string(session_id.clone())]))?;
                                }
                                Err(re) => {
                                    print_error(&format!("Failed to reconnect: {}", re));
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            Err(ReadlineError::Interrupted) => {
                println!("^C");
                continue;
            }
            Err(ReadlineError::Eof) => {
                println!("Bye.");
                break;
            }
            Err(err) => {
                print_error(&format!("Readline Error: {:?}", err));
                break;
            }
        }
    }

    Ok(())
}

fn dispatch(
    input: &str,
    stream: &mut UnixStream,
    reader: &mut BufReader<UnixStream>,
    current_session_id: &mut String,
) -> Result<Action> {
    if input.starts_with("/") {
        let parts: Vec<&str> = input.split_whitespace().collect();
        let cmd = parts[0];

        match cmd {
            "/help" => {
                println!("{BOLD}Available Commands:{RESET}");
                println!("  /help             - Show this help message");
                println!("  /exit, /quit      - Exit the CLI");
                println!("  /session [id]     - Show or switch current session");
                println!("  /sessions         - List available sessions on server");
                println!("  /history          - Show conversation history");
                println!("  /clear            - Clear current session history and environment");
                println!("  /env              - Show variables defined in REPL");
                println!("  /eval <scheme>   - Execute Scheme code directly in REPL");
                println!("  /ask <query>     - Ask a one-off question to AI (no recursion)");
                println!("  /model [name]     - Show or change the active LLM model");
                println!("  /models           - List available models");
                println!("  /thinking [on|off]- Enable or disable reasoning mode");
                Ok(Action::Continue)
            }
            "/exit" | "/quit" => Ok(Action::Exit),
            "/session" => {
                if parts.len() > 1 {
                    let new_id = parts[1].to_string();
                    *current_session_id = new_id.clone();
                    send_sexp(
                        stream,
                        &Value::list(vec![Value::symbol("session"), Value::string(new_id)]),
                    )?;
                    println!("{}[SESSION] Switching to session: {}{}", YELLOW, current_session_id, RESET);
                    // No events expected immediately, server just switches
                } else {
                    println!("{BOLD}Current Session ID:{RESET} {}", current_session_id);
                }
                Ok(Action::Continue)
            }
            "/sessions" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("list-sessions")]))?;
                receive_events(reader)?;
                Ok(Action::Continue)
            }
            "/history" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("get-history")]))?;
                receive_events(reader)?;
                Ok(Action::Continue)
            }
            "/clear" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("clear")]))?;
                println!("{}[SESSION] Environment and history cleared.{}", YELLOW, RESET);
                Ok(Action::Continue)
            }
            "/env" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("env")]))?;
                receive_events(reader)?;
                Ok(Action::Continue)
            }
            "/eval" => {
                if parts.len() > 1 {
                    let code = parts[1..].join(" ");
                    send_sexp(stream, &Value::list(vec![Value::symbol("repl"), Value::string(code)]))?;
                    receive_events(reader)?;
                } else {
                    print_error("Usage: /eval <scheme code>");
                }
                Ok(Action::Continue)
            }
            "/ask" => {
                if parts.len() > 1 {
                    let query = parts[1..].join(" ");
                    send_sexp(stream, &Value::list(vec![Value::symbol("ask"), Value::string(query)]))?;
                    receive_events(reader)?;
                } else {
                    print_error("Usage: /ask <query>");
                }
                Ok(Action::Continue)
            }
            "/model" => {
                if parts.len() > 1 {
                    let model = parts[1];
                    send_sexp(stream, &Value::list(vec![Value::symbol("set-model"), Value::string(model.to_string())]))?;
                    println!("{}[SESSION] Model changed to: {}{}", YELLOW, model, RESET);
                } else {
                    send_sexp(stream, &Value::list(vec![Value::symbol("get-model")]))?;
                    receive_events(reader)?;
                }
                Ok(Action::Continue)
            }
            "/models" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("list-models")]))?;
                receive_events(reader)?;
                Ok(Action::Continue)
            }
            "/thinking" => {
                if parts.len() > 1 {
                    let state = parts[1];
                    send_sexp(stream, &Value::list(vec![Value::symbol("set-thinking"), Value::string(state.to_string())]))?;
                    println!("{}[SESSION] Thinking mode set to: {}{}", YELLOW, state, RESET);
                } else {
                    send_sexp(stream, &Value::list(vec![Value::symbol("get-thinking")]))?;
                    receive_events(reader)?;
                }
                Ok(Action::Continue)
            }
            _ => {
                print_error(&format!("Unknown command: {}", cmd));
                Ok(Action::Continue)
            }
        }
    } else {
        // Standard query
        send_sexp(
            stream,
            &Value::list(vec![Value::symbol("eval"), Value::string(input.to_string())]),
        )?;
        receive_events(reader)?;
        Ok(Action::Continue)
    }
}

fn receive_events(reader: &mut BufReader<UnixStream>) -> Result<()> {
    loop {
        match protocol::receive_event(reader)? {
            Some(event) => {
                if let Value::Cons(cons) = &event {
                    let tag = cons.car().as_symbol().unwrap_or("");
                    let cdr = cons.cdr();

                    match tag {
                        "status" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    print_status(msg);
                                }
                            }
                        }
                        "thought" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    print!("{DIM}");
                                    print_markdown(msg);
                                    print!("{RESET}");
                                }
                            }
                        }
                        "result" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(res) = c.car().as_str() {
                                    print_result(&format!("✔ Result: {}", res));
                                }
                            }
                        }
                        "repl-result" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(res) = c.car().as_str() {
                                    print_result(&format!("✔ Result: {}", res));
                                }
                            }
                            return Ok(()); // Terminal for /eval
                        }
                        "final" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(ans) = c.car().as_str() {
                                    eprintln!(); // Clear status
                                    println!("\n{BOLD}Final Answer:{RESET}");
                                    print_markdown(ans);
                                }
                            }
                            return Ok(()); // Terminal for /eval (ask)
                        }
                        "session-list" => {
                            println!("{BOLD}Available Sessions:{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_list(c.car());
                            }
                            return Ok(()); // Terminal for /sessions
                        }
                        "history-list" => {
                            println!("\n{BOLD}--- Conversation History ---\n{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_history(c.car());
                            }
                            println!("\n{BOLD}--- End of History ---\n{RESET}");
                            return Ok(()); // Terminal for /history
                        }
                        "env-list" => {
                            println!("{BOLD}REPL Bindings:{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_env_bindings(c.car());
                            }
                            return Ok(()); // Terminal for /env
                        }
                        "model-info" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(model) = c.car().as_str() {
                                    println!("{BOLD}Active Model:{RESET} {}", model);
                                }
                            }
                            return Ok(()); // Terminal for /model
                        }
                        "models-list" => {
                            println!("{BOLD}Available Models:{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_list(c.car());
                            }
                            return Ok(()); // Terminal for /models
                        }
                        "thinking-info" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(state) = c.car().as_str() {
                                    println!("{BOLD}Thinking Mode:{RESET} {}", state);
                                }
                            }
                            return Ok(()); // Terminal for /thinking
                        }
                        "info" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    println!("{}Info: {}{}", CYAN, msg, RESET);
                                }
                            }
                            return Ok(()); // Terminal for general info responses
                        }
                        "error" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    print_error(&format!("Error: {}", msg));
                                }
                            }
                            return Ok(()); // Terminal for errors
                        }
                        _ => {
                            // Unknown tag, just continue
                        }
                    }
                }
            }
            None => return Ok(()), // EOF
        }
    }
}
