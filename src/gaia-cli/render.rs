use lexpr::Value;
use pulldown_cmark::{Parser, Event, Tag, TagEnd};
use regex::Regex;
use syntect::easy::HighlightLines;
use syntect::parsing::SyntaxSet;
use syntect::highlighting::{ThemeSet, Style};
use syntect::util::as_24_bit_terminal_escaped;

pub const BOLD: &str = "\x1b[1m";
pub const DIM: &str = "\x1b[2m";
pub const RED: &str = "\x1b[31m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const CYAN: &str = "\x1b[36m";
pub const MAGENTA: &str = "\x1b[35m";
pub const BLUE: &str = "\x1b[34m";
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


pub fn print_status(msg: &str) {
    eprint!("\r{}{}{}{}", DIM, msg, " ".repeat(10), RESET);
}

pub fn print_result(msg: &str) {
    println!("{}{}{}", GREEN, msg, RESET);
}

pub fn print_error(msg: &str) {
    println!("{}{}{}", RED, msg, RESET);
}

fn clean_assistant_content(text: &str) -> String {
    let mut cleaned = text.to_string();

    // 1. Strip <confidence>...</confidence> and CONFIDENCE(...)
    if let Ok(re) = Regex::new(r"(?s)<confidence>\d+</confidence>") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }
    if let Ok(re) = Regex::new(r"CONFIDENCE\(\d+\)") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    // 2. Strip FINAL(...) and FINAL_VAR(...)
    if let Ok(re) = Regex::new(r"(?s)FINAL\([^)]*\)") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }
    if let Ok(re) = Regex::new(r"(?s)FINAL_VAR\([^)]*\)") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    // 3. Strip Scheme code blocks entirely to keep conversation clean
    if let Ok(re) = Regex::new(r"(?s)```repl.*?```") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }
    if let Ok(re) = Regex::new(r"(?s)```scheme.*?```") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    // 4. Strip <|think|>...</|think|> blocks
    if let Ok(re) = Regex::new(r"(?s)<\|think\|>.*?</\|think\|>") {
        cleaned = re.replace_all(&cleaned, "").to_string();
    }

    let trimmed = cleaned.trim().to_string();
    if trimmed.is_empty() {
        format!("{DIM}[State Update / Internal Execution]{RESET}")
    } else {
        trimmed
    }
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
                let cleaned = if role == "assistant" {
                    clean_assistant_content(&content)
                } else {
                    content
                };
                print_markdown(&cleaned);
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
