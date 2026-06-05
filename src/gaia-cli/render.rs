use lexpr::Value;
use pulldown_cmark::{Parser, Event, Tag, TagEnd};
use syntect::easy::HighlightLines;
use syntect::parsing::SyntaxSet;
use syntect::highlighting::{ThemeSet, Style};
use syntect::util::as_24_bit_terminal_escaped;
use similar::{ChangeTag, TextDiff};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::{self, JoinHandle};
use std::time::Duration;
use std::io::{self, Write};

pub const BOLD: &str = "\x1b[1m";
pub const DIM: &str = "\x1b[2m";
pub const RED: &str = "\x1b[31m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const CYAN: &str = "\x1b[36m";
pub const RESET: &str = "\x1b[0m";

/// Print Scheme code with syntax highlighting inside a premium ASCII box
pub fn print_scheme(code: &str) {
    let ps = SyntaxSet::load_defaults_newlines();
    let ts = ThemeSet::load_defaults();

    let syntax = ps.find_syntax_by_extension("scm")
        .or_else(|| ps.find_syntax_by_name("Scheme"))
        .unwrap_or_else(|| ps.find_syntax_plain_text());

    let theme = &ts.themes["base16-ocean.dark"];
    let mut h = HighlightLines::new(syntax, theme);

    println!("\n{}╭─ scheme ───────────────────────────────────────────────────────────{}", DIM, RESET);
    for line in code.lines() {
        let ranges: Vec<(Style, &str)> = h.highlight_line(line, &ps).unwrap_or_default();
        let escaped = as_24_bit_terminal_escaped(&ranges[..], false);
        println!("{}│{} {}", DIM, RESET, escaped);
    }
    println!("{}╰───────────────────────────────────────────────────────────────────{}\n", DIM, RESET);
}


pub fn print_result(msg: &str) {
    println!("{}{}{}", GREEN, msg, RESET);
}

pub fn print_error(msg: &str) {
    println!("{}{}{}", RED, msg, RESET);
}

pub fn print_history(val: &Value) {
    match val {
        Value::Null => println!("  (no history)"),
        Value::Cons(cons) => {
            let mut current = Value::Cons(cons.clone());
            while let Value::Cons(pair) = current {
                let turn = pair.car();
                let mut role = "unknown".to_string();
                let mut content = "".to_string();

                // turn is an alist: (("content" . "...") ("role" . "..."))
                if let Value::Cons(alist) = turn {
                    let mut items = Value::Cons(alist.clone());
                    while let Value::Cons(item_pair) = items {
                        if let Value::Cons(kv) = item_pair.car() {
                            let k = kv.car().as_str().unwrap_or("");
                            let v = kv.cdr().as_str().unwrap_or("");
                            if k == "role" { role = v.to_string(); }
                            if k == "content" { content = v.to_string(); }
                        }
                        items = item_pair.cdr().clone();
                    }
                }

                let color = match role.as_str() {
                    "user" => GREEN,
                    "assistant" => YELLOW,
                    _ => DIM,
                };
                let display_name = match role.as_str() {
                    "user" => "USER",
                    "assistant" => "GAIA",
                    _ => "UNKNOWN",
                };

                println!("{}{} >{} ", color, display_name, RESET);
                print_markdown(&content);
                println!("{}", "—".repeat(40));

                current = pair.cdr().clone();
            }
        }
        _ => println!("  {}", val),
    }
}

pub fn print_markdown(text: &str) {
    let parser = Parser::new(text);
    for event in parser {
        match event {
            Event::Text(t) => print!("{}", t),
            Event::Code(c) => print!("{}{}{}", CYAN, c, RESET),
            Event::Start(Tag::Strong) => print!("{}", BOLD),
            Event::End(TagEnd::Strong) => print!("{}", RESET),
            Event::Start(Tag::Emphasis) => print!("\x1b[3m"),
            Event::End(TagEnd::Emphasis) => print!("{}", RESET),
            Event::Start(Tag::Heading { .. }) => print!("\n{}", BOLD),
            Event::End(TagEnd::Heading { .. }) => print!("{}\n", RESET),
            Event::SoftBreak | Event::HardBreak => println!(),
            _ => {}
        }
    }
    println!();
}

pub fn print_env_bindings(val: &Value) {
    match val {
        Value::Null => {
            println!("  {}(empty){}", DIM, RESET);
        }
        Value::Cons(cons) => {
            let mut current = Value::Cons(cons.clone());
            while let Value::Cons(pair) = current {
                let entry = pair.car();
                if let Value::Cons(kv) = entry {
                    let key = kv.car();
                    let val = kv.cdr();
                    println!("  {} = {}", key, val);
                }
                current = pair.cdr().clone();
            }
        }
        _ => {
            println!("  {}", val);
        }
    }
}

pub fn print_list(val: &Value) {
    match val {
        Value::Null => {
            println!("  {}(none){}", DIM, RESET);
        }
        Value::Cons(cons) => {
            let mut current = Value::Cons(cons.clone());
            while let Value::Cons(pair) = current {
                println!("  - {}", pair.car());
                current = pair.cdr().clone();
            }
        }
        _ => {
            println!("  {}", val);
        }
    }
}

pub fn print_file_diff(path: &str, new_content: &str) {
    let old_content = std::fs::read_to_string(path).unwrap_or_default();
    let diff = TextDiff::from_lines(old_content.as_str(), new_content);
    
    println!("\n{}╭─ diff: {} ───────────────────────────────────────────────────────────{}", DIM, path, RESET);
    for change in diff.iter_all_changes() {
        match change.tag() {
            ChangeTag::Delete => {
                print!("{}{}- {}{}", RED, BOLD, change, RESET);
            }
            ChangeTag::Insert => {
                print!("{}{}+ {}{}", GREEN, BOLD, change, RESET);
            }
            ChangeTag::Equal => {
                print!("  {}", change);
            }
        }
    }
    println!("{}╰───────────────────────────────────────────────────────────────────{}\n", DIM, RESET);
}

pub struct Spinner {
    active: Arc<AtomicBool>,
    message: Arc<Mutex<String>>,
    handle: Option<JoinHandle<()>>,
}

impl Spinner {
    pub fn new() -> Self {
        Self {
            active: Arc::new(AtomicBool::new(false)),
            message: Arc::new(Mutex::new(String::new())),
            handle: None,
        }
    }

    pub fn start(&mut self, initial_msg: &str) {
        if self.active.load(Ordering::SeqCst) {
            self.update(initial_msg);
            return;
        }

        self.active.store(true, Ordering::SeqCst);
        *self.message.lock().unwrap() = initial_msg.to_string();

        let active = Arc::clone(&self.active);
        let message = Arc::clone(&self.message);

        let handle = thread::spawn(move || {
            let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
            let mut i = 0;
            while active.load(Ordering::SeqCst) {
                let msg = message.lock().unwrap().clone();
                eprint!("\r\x1b[36m{}\x1b[0m \x1b[2m{}\x1b[0m", frames[i], msg);
                let _ = io::stderr().flush();
                thread::sleep(Duration::from_millis(80));
                i = (i + 1) % frames.len();
            }
            eprint!("\r\x1b[K");
            let _ = io::stderr().flush();
        });

        self.handle = Some(handle);
    }

    pub fn update(&self, new_msg: &str) {
        if self.active.load(Ordering::SeqCst) {
            *self.message.lock().unwrap() = new_msg.to_string();
        }
    }

    pub fn stop(&mut self) {
        if self.active.load(Ordering::SeqCst) {
            self.active.store(false, Ordering::SeqCst);
            if let Some(handle) = self.handle.take() {
                let _ = handle.join();
            }
        }
    }
}

impl Drop for Spinner {
    fn drop(&mut self) {
        self.stop();
    }
}
