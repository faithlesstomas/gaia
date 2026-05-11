use anyhow::Result;
use lexpr::Value;
use rustyline::error::ReadlineError;
use rustyline::DefaultEditor;
use std::io::BufReader;
use std::os::unix::net::UnixStream;
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;

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

/// Events forwarded from the listener thread to the main thread.
/// Only "end-of-operation" events are forwarded. Informational events
/// (status, thought, result, stream-log, info) are printed directly
/// by the listener thread to keep the socket drained at all times.
enum ServerEvent {
    /// A terminal event that ends a wait_and_print() call
    Terminal(Value),
    /// Server closed the connection
    Closed,
}

fn main() -> Result<()> {
    println!("\n{BOLD}{GREEN}GAIA CLI {}{RESET}", env!("GAIA_VERSION"));
    println!("Type {BOLD}/help{RESET} for commands or enter a task.\n");

    let mut session_id = format!(
        "gaia-cli-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs()
    );

    let mut stream = connect_with_retry(SOCKET_PATH)?;

    // Send initial session message
    send_sexp(
        &mut stream,
        &Value::list(vec![
            Value::symbol("session"),
            Value::string(session_id.clone()),
        ]),
    )?;

    // Spawn background listener thread
    let reader_stream = stream.try_clone()?;
    let (tx, rx): (Sender<ServerEvent>, Receiver<ServerEvent>) = mpsc::channel();
    thread::spawn(move || {
        let mut reader = BufReader::new(reader_stream);
        listener_loop(&mut reader, tx);
    });

    // The initial (session ...) produces an (info ...) ack from the server.
    // Since 'info' is now a display-only event (printed by listener thread),
    // we do NOT need to consume it here. The listener thread handles it.

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

                match dispatch(trimmed, &mut stream, &rx, &mut session_id) {
                    Ok(Action::Exit) => break,
                    Ok(Action::Continue) => {}
                    Err(e) => {
                        print_error(&format!("Error: {}", e));
                        break;
                    }
                }
            }
            Err(ReadlineError::Interrupted) => {
                println!("^C (Sending interrupt to server...)");
                if let Ok(pid_str) = std::fs::read_to_string("/tmp/gaia.pid") {
                    if let Ok(pid) = pid_str.trim().parse::<i32>() {
                        let _ = std::process::Command::new("kill")
                            .arg("-SIGINT")
                            .arg(pid.to_string())
                            .status();
                    }
                }
                let _ = send_sexp(
                    &mut stream,
                    &Value::list(vec![Value::symbol("interrupt")]),
                );
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

/// Background listener: reads ALL events from server, prints display-events
/// immediately, and forwards terminal-events to the main thread via channel.
fn listener_loop(reader: &mut BufReader<UnixStream>, tx: Sender<ServerEvent>) {
    loop {
        match protocol::receive_event(reader) {
            Ok(Some(event)) => {
                if let Value::Cons(cons) = &event {
                    let tag = cons.car().as_symbol().unwrap_or("");
                    let cdr = cons.cdr();

                    match tag {
                        // === DISPLAY-ONLY EVENTS ===
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
                                    eprint!("\r\x1b[K"); // clear status line
                                    println!("\n{DIM}💭 Thinking:{RESET}");
                                    println!("{DIM}{}{RESET}", msg);
                                }
                            }
                        }
                        "analysis" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    eprint!("\r\x1b[K");
                                    println!("\n{BOLD}📋 Analysis:{RESET}");
                                    print_markdown(msg);
                                }
                            }
                        }
                        "code" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(code) = c.car().as_str() {
                                    eprint!("\r\x1b[K");
                                    println!("\n{CYAN}{BOLD}▶ Executing Scheme:{RESET}");
                                    print_scheme(code);
                                }
                            }
                        }
                        "result" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(res) = c.car().as_str() {
                                    println!("{GREEN}✔ Result:{RESET} {}", truncate_output(res, 500));
                                }
                            }
                        }
                        "repl-error" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    println!("{RED}✘ REPL Error:{RESET} {}", msg);
                                }
                            }
                        }
                        "stream-log" | "log" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    println!("{DIM}{}{RESET}", msg);
                                }
                            }
                        }
                        "info" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    println!("{CYAN}ℹ {}{RESET}", msg);
                                }
                            }
                        }

                        // === TERMINAL EVENTS ===
                        "final" | "repl-result" | "error"
                        | "session-list" | "history-list" | "env-list"
                        | "model-info" | "models-list" | "thinking-info" 
                        | "permission-request" => {
                            // Clear any residual status line before forwarding
                            eprint!("\r\x1b[K");
                            if tx.send(ServerEvent::Terminal(event.clone())).is_err() {
                                return;
                            }
                        }

                        _ => {
                            println!("{DIM}[?event: {}]{RESET}", tag);
                        }
                    }
                }
            }
            Ok(None) => {
                let _ = tx.send(ServerEvent::Closed);
                return;
            }
            Err(e) => {
                eprintln!("{RED}Listener error: {}{RESET}", e);
                let _ = tx.send(ServerEvent::Closed);
                return;
            }
        }
    }
}

fn truncate_output(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}...\n{DIM}[output truncated: {} chars total]{RESET}", &s[..max], s.len())
    }
}

fn dispatch(
    input: &str,
    stream: &mut UnixStream,
    rx: &Receiver<ServerEvent>,
    current_session_id: &mut String,
) -> Result<Action> {
    if input.starts_with('/') {
        let parts: Vec<&str> = input.split_whitespace().collect();
        let cmd = parts[0];

        match cmd {
            "/help" => {
                show_help();
                Ok(Action::Continue)
            }
            "/exit" | "/quit" => Ok(Action::Exit),

            // --- Session management (no wait — info printed by listener) ---
            "/session" => {
                if parts.len() > 1 {
                    let new_id = parts[1].to_string();
                    *current_session_id = new_id.clone();
                    send_sexp(
                        stream,
                        &Value::list(vec![
                            Value::symbol("session"),
                            Value::string(new_id),
                        ]),
                    )?;
                    // Server sends (info ...) which listener prints directly
                } else {
                    println!("{BOLD}Current Session ID:{RESET} {}", current_session_id);
                }
                Ok(Action::Continue)
            }
            "/sessions" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("list-sessions")]))?;
                wait_and_print(rx, stream)?;
                Ok(Action::Continue)
            }
            "/history" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("get-history")]))?;
                wait_and_print(rx, stream)?;
                Ok(Action::Continue)
            }
            "/clear" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("clear")]))?;
                // Server sends (info ...) which listener prints directly
                Ok(Action::Continue)
            }
            "/env" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("env")]))?;
                wait_and_print(rx, stream)?;
                Ok(Action::Continue)
            }
            "/eval" => {
                if parts.len() > 1 {
                    let code = parts[1..].join(" ");
                    send_sexp(
                        stream,
                        &Value::list(vec![
                            Value::symbol("repl"),
                            Value::string(code),
                        ]),
                    )?;
                    wait_and_print(rx, stream)?;
                } else {
                    print_error("Usage: /eval <scheme code>");
                }
                Ok(Action::Continue)
            }
            "/ask" => {
                if parts.len() > 1 {
                    let query = parts[1..].join(" ");
                    send_sexp(
                        stream,
                        &Value::list(vec![
                            Value::symbol("ask"),
                            Value::string(query),
                        ]),
                    )?;
                    wait_and_print(rx, stream)?;
                } else {
                    print_error("Usage: /ask <query>");
                }
                Ok(Action::Continue)
            }

            // --- Model/thinking: set = fire-and-forget, get = wait ---
            "/model" => {
                if parts.len() > 1 {
                    let model = parts[1];
                    send_sexp(
                        stream,
                        &Value::list(vec![
                            Value::symbol("set-model"),
                            Value::string(model.to_string()),
                        ]),
                    )?;
                    // Server sends (info ...) which listener prints directly
                } else {
                    send_sexp(stream, &Value::list(vec![Value::symbol("get-model")]))?;
                    wait_and_print(rx, stream)?;
                }
                Ok(Action::Continue)
            }
            "/models" => {
                send_sexp(stream, &Value::list(vec![Value::symbol("list-models")]))?;
                wait_and_print(rx, stream)?;
                Ok(Action::Continue)
            }
            "/thinking" => {
                if parts.len() > 1 {
                    let state = parts[1];
                    send_sexp(
                        stream,
                        &Value::list(vec![
                            Value::symbol("set-thinking"),
                            Value::string(state.to_string()),
                        ]),
                    )?;
                    // Server sends (info ...) which listener prints directly
                } else {
                    send_sexp(stream, &Value::list(vec![Value::symbol("get-thinking")]))?;
                    wait_and_print(rx, stream)?;
                }
                Ok(Action::Continue)
            }
            _ => {
                print_error(&format!("Unknown command: {}", cmd));
                Ok(Action::Continue)
            }
        }
    } else {
        // Standard query — send eval, wait for final/error
        send_sexp(
            stream,
            &Value::list(vec![
                Value::symbol("eval"),
                Value::string(input.to_string()),
            ]),
        )?;
        wait_and_print(rx, stream)?;
        Ok(Action::Continue)
    }
}

/// Block until the listener thread forwards a terminal event.
/// During this time, the listener thread continues printing
/// status/thought/result/stream-log/info events in real-time.
fn wait_and_print(rx: &Receiver<ServerEvent>, stream: &mut UnixStream) -> Result<()> {
    loop {
        match rx.recv()? {
            ServerEvent::Terminal(event) => {
                if let Value::Cons(cons) = &event {
                    let tag = cons.car().as_symbol().unwrap_or("");
                    let cdr = cons.cdr();

                    match tag {
                        "permission-request" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(req) = c.car().as_str() {
                                    println!("\n{BOLD}{YELLOW}⚠ Permission Request:{RESET} {}", req);
                                    let mut input = String::new();
                                    loop {
                                        print!("Allow execution? (y/N): ");
                                        use std::io::Write;
                                        std::io::stdout().flush()?;
                                        input.clear();
                                        std::io::stdin().read_line(&mut input)?;
                                        let ans = input.trim().to_lowercase();
                                        if ans == "y" || ans == "yes" {
                                            send_sexp(stream, &Value::list(vec![Value::symbol("permission-response"), Value::Bool(true)]))?;
                                            break;
                                        } else if ans == "" || ans == "n" || ans == "no" {
                                            send_sexp(stream, &Value::list(vec![Value::symbol("permission-response"), Value::Bool(false)]))?;
                                            break;
                                        }
                                    }
                                }
                            }
                            continue; // Wait for the NEXT terminal event (e.g. repl-result or error)
                        }
                        "repl-result" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(res) = c.car().as_str() {
                                    print_result(&format!("✔ Result: {}", res));
                                }
                            }
                            break;
                        }
                        "final" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(ans) = c.car().as_str() {
                                    println!("\n{BOLD}Final Answer:{RESET}");
                                    print_markdown(ans);
                                }
                            }
                            break;
                        }
                        "session-list" => {
                            println!("{BOLD}Available Sessions:{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_list(c.car());
                            }
                            break;
                        }
                        "history-list" => {
                            println!("\n{BOLD}--- Conversation History ---\n{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_history(c.car());
                            }
                            println!("\n{BOLD}--- End of History ---\n{RESET}");
                            break;
                        }
                        "env-list" => {
                            println!("{BOLD}REPL Bindings:{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_env_bindings(c.car());
                            }
                            break;
                        }
                        "model-info" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(model) = c.car().as_str() {
                                    println!("{BOLD}Active Model:{RESET} {}", model);
                                }
                            }
                            break;
                        }
                        "models-list" => {
                            println!("{BOLD}Available Models:{RESET}");
                            if let Value::Cons(c) = cdr {
                                print_list(c.car());
                            }
                            break;
                        }
                        "thinking-info" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(state) = c.car().as_str() {
                                    println!("{BOLD}Thinking Mode:{RESET} {}", state);
                                }
                            }
                            break;
                        }
                        "error" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    print_error(&format!("Error: {}", msg));
                                }
                            }
                            break;
                        }
                        _ => {
                            break;
                        }
                    }
                }
            }
            ServerEvent::Closed => return Err(anyhow::anyhow!("Connection closed by server")),
        }
    }
    Ok(())
}

fn show_help() {
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
}
