use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::{Backend, CrosstermBackend},
    layout::{Constraint, Direction, Layout},
    widgets::{Block, Borders, Paragraph},
    Frame, Terminal,
};
use std::io;
use std::sync::{Arc, Mutex};
use tokio::net::UnixStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[derive(Clone)]
struct AppState {
    events: Arc<Mutex<Vec<String>>>,
    status: Arc<Mutex<String>>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let state = AppState {
        events: Arc::new(Mutex::new(Vec::new())),
        status: Arc::new(Mutex::new("Disconnected".to_string())),
    };

    // Spawn networking task
    let state_clone = state.clone();
    tokio::spawn(async move {
        if let Err(e) = run_networking(state_clone).await {
            eprintln!("Networking error: {:?}", e);
        }
    });

    // Main loop
    let res = run_app(&mut terminal, state).await;

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(err) = res {
        println!("{:?}", err)
    }

    Ok(())
}

async fn run_networking(state: AppState) -> Result<()> {
    let socket_path = "/tmp/gaia.sock";
    let mut stream = UnixStream::connect(socket_path).await?;
    {
        let mut status = state.status.lock().unwrap();
        *status = "Connected to Headless Engine".to_string();
    }

    // Send initial test eval
    let cmd = "(eval \"List all files in the current directory and explain what this project is about.\")\n";
    stream.write_all(cmd.as_bytes()).await?;

    let mut buffer = [0; 4096];
    loop {
        let n = stream.read(&mut buffer).await?;
        if n == 0 { break; }
        
        let chunk = String::from_utf8_lossy(&buffer[..n]);
        // For now, we just split by newline and add to events
        // In a real app, we would parse S-expressions with lexpr
        for line in chunk.lines() {
            if !line.trim().is_empty() {
                let mut events = state.events.lock().unwrap();
                events.push(line.to_string());
            }
        }
    }

    Ok(())
}

async fn run_app<B: Backend>(terminal: &mut Terminal<B>, state: AppState) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui(f, &state))?;

        if event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                if let KeyCode::Char('q') = key.code {
                    return Ok(());
                }
            }
        }
    }
}

fn ui(f: &mut Frame, state: &AppState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(
            [
                Constraint::Length(3),
                Constraint::Min(10),
                Constraint::Length(3),
            ]
            .as_ref(),
        )
        .split(f.size());

    let status_text = state.status.lock().unwrap();
    let header = Paragraph::new(status_text.clone())
        .block(Block::default().borders(Borders::ALL).title("Status (GAIA v0.2.0)"));
    f.render_widget(header, chunks[0]);

    let events = state.events.lock().unwrap();
    let body_text = events.join("\n");
    let body = Paragraph::new(body_text)
        .block(Block::default().borders(Borders::ALL).title("Engine Event Stream"));
    f.render_widget(body, chunks[1]);

    let footer = Paragraph::new("Press 'q' to quit. Interaction coming soon...")
        .block(Block::default().borders(Borders::ALL).title("Input"));
    f.render_widget(footer, chunks[2]);
}
