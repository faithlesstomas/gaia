use lexpr::Value;
use syntect::easy::HighlightLines;
use syntect::parsing::SyntaxSet;
use syntect::highlighting::{ThemeSet, Style};
use syntect::util::as_24_bit_terminal_escaped;
use pulldown_cmark::{Parser, Event, Tag, TagEnd};

pub const BOLD: &str = "\x1b[1m";
pub const DIM: &str = "\x1b[2m";
pub const RED: &str = "\x1b[31m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const CYAN: &str = "\x1b[36m";
pub const RESET: &str = "\x1b[0m";

pub fn print_status(msg: &str) {
    eprint!("\r{}{}{}{}", DIM, msg, " ".repeat(10), RESET);
}

pub fn print_result(msg: &str) {
    println!("{}{}{}", GREEN, msg, RESET);
}

pub fn print_error(msg: &str) {
    println!("{}{}{}", RED, msg, RESET);
}

pub fn print_code(code: &str) {
    let ps = SyntaxSet::load_defaults_newlines();
    let ts = ThemeSet::load_defaults();

    let syntax = ps.find_syntax_by_extension("scm")
        .or_else(|| ps.find_syntax_by_name("Scheme"))
        .unwrap_or_else(|| ps.find_syntax_plain_text());
    
    let theme = &ts.themes["base16-ocean.dark"];
    let mut h = HighlightLines::new(syntax, theme);

    println!("\n{}╭─ scheme ─────────────────────────────────────{}", DIM, RESET);
    for line in code.lines() {
        let ranges: Vec<(Style, &str)> = h.highlight_line(line, &ps).unwrap_or_default();
        let escaped = as_24_bit_terminal_escaped(&ranges[..], false);
        println!("{}│{} {}", DIM, RESET, escaped);
    }
    println!("{}╰──────────────────────────────────────────────{}\n", DIM, RESET);
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
