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

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

fn main() -> Result<()> {
    let running_agent = Arc::new(AtomicBool::new(false));
    let mut session_id = format!(
        "gaia-cli-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs()
    );

    println!("\n{BOLD}{GREEN}GAIA CLI {}{RESET}", env!("GAIA_VERSION"));
    println!("Type {BOLD}/help{RESET} for commands or enter a task.\n");

    let mut stream = connect_with_retry(SOCKET_PATH)?;

    let mut interrupt_stream = stream.try_clone()?;
    let ctrlc_running = Arc::clone(&running_agent);
    ctrlc::set_handler(move || {
        if ctrlc_running.load(Ordering::SeqCst) {
            // Send explicit interrupt message over the socket
            let _ = send_sexp(
                &mut interrupt_stream,
                &Value::list(vec![Value::symbol("interrupt")]),
            );

            println!("\n{YELLOW}^C (Agent interrupted by user){RESET}");
        } else {
            // At prompt - just show hint
            println!("\n{CYAN}Info: Type /exit or /quit to close GAIA.{RESET}");
        }
    })?;

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

    let mut rl = DefaultEditor::new()?;

    loop {
        let prompt = format!("{}(GAIA) > {}", GREEN, RESET);
        running_agent.store(false, Ordering::SeqCst);
        let readline = rl.readline(&prompt);

        match readline {
            Ok(line) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                let _ = rl.add_history_entry(trimmed);

                running_agent.store(true, Ordering::SeqCst);
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
                // Should not happen with check_signals(false), but handled for safety
                println!("\n{CYAN}Info: Type /exit or /quit to close GAIA.{RESET}");
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
    let mut in_token_stream = false;
    let mut in_thought_stream = false;
    let mut spinner = Spinner::new();

    loop {
        match protocol::receive_event(reader) {
            Ok(Some(event)) => {
                if let Value::Cons(cons) = &event {
                    let tag = cons.car().as_symbol().unwrap_or("");
                    let cdr = cons.cdr();

                    if tag != "status" && tag != "stream-log" && tag != "log" {
                        spinner.stop();
                    }

                    match tag {
                        // === STREAMING EVENTS ===
                        "token" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    if !in_token_stream {
                                        eprint!("\r\x1b[K"); // clear status
                                        println!("\n{BOLD}Analysis >{RESET}");
                                        in_token_stream = true;
                                        in_thought_stream = false;
                                    }
                                    print!("{}", msg);
                                    use std::io::Write;
                                    std::io::stdout().flush().unwrap();
                                }
                            }
                        }
                        "thought" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    if !in_thought_stream {
                                        eprint!("\r\x1b[K"); // clear status
                                        println!("\n{DIM}Thinking >{RESET}");
                                        in_thought_stream = true;
                                        in_token_stream = false;
                                    }
                                    print!("{DIM}{}{RESET}", msg);
                                    use std::io::Write;
                                    std::io::stdout().flush().unwrap();
                                }
                            }
                        }

                        // === DISPLAY-ONLY EVENTS ===
                        "status" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    spinner.start(msg);
                                }
                            }
                        }
                        "analysis" => {
                            // Full analysis event (fallback or final summary)
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    if !in_token_stream {
                                        eprint!("\r\x1b[K");
                                        println!("\n{BOLD}Analysis >{RESET}");
                                    } else {
                                        println!(); // finish the stream line
                                    }
                                    print_markdown(msg);
                                    in_token_stream = false;
                                    in_thought_stream = false;
                                }
                            }
                        }
                        "code" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(code) = c.car().as_str() {
                                    eprint!("\r\x1b[K");
                                    if in_token_stream || in_thought_stream {
                                        println!();
                                    }
                                    println!("\n{CYAN}{BOLD}Executing Scheme >{RESET}");
                                    print_scheme(code);
                                    in_token_stream = false;
                                    in_thought_stream = false;
                                }
                            }
                        }
                        "result" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(res) = c.car().as_str() {
                                    println!("{GREEN}Result >{RESET} {}", truncate_output(res, 500));
                                }
                            }
                        }
                        "repl-error" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(msg) = c.car().as_str() {
                                    println!("{RED}REPL Error >{RESET} {}", msg);
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
                                    println!("{CYAN}Info > {}{RESET}", msg);
                                }
                            }
                        }

                        // === TERMINAL EVENTS ===
                        "final" | "repl-result" | "error"
                        | "session-list" | "history-list" | "env-list"
                        | "model-info" | "models-list" | "thinking-info" 
                        | "permission-request" => {
                            if in_token_stream || in_thought_stream {
                                println!();
                            }
                            // Clear any residual status line before forwarding
                            eprint!("\r\x1b[K");
                            if tx.send(ServerEvent::Terminal(event.clone())).is_err() {
                                return;
                            }
                            in_token_stream = false;
                            in_thought_stream = false;
                        }

                        _ => {
                            println!("{DIM}[?event: {}]{RESET}", tag);
                        }
                    }
                }
            }
            Ok(None) => {
                spinner.stop();
                let _ = tx.send(ServerEvent::Closed);
                return;
            }
            Err(e) => {
                spinner.stop();
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

fn edit_prompt_in_editor() -> Result<Option<String>> {
    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
    let temp_dir = std::env::temp_dir();
    let temp_path = temp_dir.join("gaia_prompt.scm");
    
    // Create an empty file
    std::fs::write(&temp_path, "")?;
    
    let status = std::process::Command::new(&editor)
        .arg(&temp_path)
        .status()?;
        
    if status.success() {
        let content = std::fs::read_to_string(&temp_path)?;
        let _ = std::fs::remove_file(&temp_path);
        if content.trim().is_empty() {
            Ok(None)
        } else {
            Ok(Some(content))
        }
    } else {
        let _ = std::fs::remove_file(&temp_path);
        Err(anyhow::anyhow!("Editor exited with error status"))
    }
}

fn dispatch(
    input: &str,
    stream: &mut UnixStream,
    rx: &Receiver<ServerEvent>,
    current_session_id: &mut String,
) -> Result<Action> {
    let parts: Vec<&str> = input.split_whitespace().collect();
    if parts.is_empty() {
        return Ok(Action::Continue);
    }
    let cmd = parts[0];

    match cmd {
        "/exit" | "/quit" => Ok(Action::Exit),
        "/help" => {
            show_help();
            Ok(Action::Continue)
        }
        "/edit" | "/e" => {
            if let Some(edited_prompt) = edit_prompt_in_editor()? {
                let trimmed = edited_prompt.trim();
                if !trimmed.is_empty() {
                    dispatch(trimmed, stream, rx, current_session_id)?;
                }
            }
            Ok(Action::Continue)
        }
        _ => {
            // Send everything else directly as raw string `(eval input)` to the server
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
                                let expr = c.car();
                                
                                let mut handled_diff = false;
                                if let Value::Cons(expr_cons) = expr {
                                    if let Some("write-file") = expr_cons.car().as_symbol() {
                                        if let Value::Cons(path_cons) = expr_cons.cdr() {
                                            if let Some(path) = path_cons.car().as_str() {
                                                if let Value::Cons(content_cons) = path_cons.cdr() {
                                                    if let Some(content) = content_cons.car().as_str() {
                                                        println!("\n{BOLD}{YELLOW}Permission Request: Write File{RESET}");
                                                        print_file_diff(path, content);
                                                        handled_diff = true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                if !handled_diff {
                                    println!("\n{BOLD}{YELLOW}Permission Request: Execute Scheme Expression{RESET}");
                                    let expr_str = format!("{}", expr);
                                    print_scheme(&expr_str);
                                }

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
                            continue; // Wait for the NEXT terminal event (e.g. repl-result or error)
                        }
                        "repl-result" => {
                            if let Value::Cons(c) = cdr {
                                if let Some(res) = c.car().as_str() {
                                    print_result(&format!("Result: {}", res));
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
