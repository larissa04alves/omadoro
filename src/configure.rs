//! TUI (ratatui) do passo de configuração: escolher a posição na waybar e a cor.
//!
//! A interface é desenhada em **stderr** para que o resultado escolhido possa
//! sair limpo em **stdout** (`posição tema`), consumido pelos scripts de install.

use std::io::{self, Stderr};

use ratatui::backend::CrosstermBackend;
use ratatui::crossterm::event::{self, Event, KeyCode, KeyEventKind};
use ratatui::crossterm::execute;
use ratatui::crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::Span;
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph};
use ratatui::{Frame, Terminal};

pub struct Choice {
    pub position: &'static str,
    pub theme: &'static str,
}

/// (chave, rótulo)
const POSITIONS: [(&str, &str); 3] = [
    ("left", "Esquerda"),
    ("center", "Centro"),
    ("right", "Direita"),
];

/// (chave, rótulo, cor de destaque)
const THEMES: [(&str, &str, Color); 3] = [
    ("sage", "Sage — verde-musgo suave", Color::Rgb(0x9c, 0xcc, 0xae)),
    ("lavanda", "Lavanda — lilás macio", Color::Rgb(0xb9, 0xa7, 0xe6)),
    ("nevoamar", "Névoa-mar — teal sereno", Color::Rgb(0x7f, 0xc9, 0xc0)),
];

/// Roda o wizard. Devolve a escolha, ou `None` se cancelado.
pub fn run() -> Option<Choice> {
    enable_raw_mode().ok()?;
    let mut stderr = io::stderr();
    if execute!(stderr, EnterAlternateScreen).is_err() {
        let _ = disable_raw_mode();
        return None;
    }
    let mut terminal = match Terminal::new(CrosstermBackend::new(stderr)) {
        Ok(t) => t,
        Err(_) => {
            let _ = disable_raw_mode();
            return None;
        }
    };

    let result = wizard(&mut terminal);

    let _ = disable_raw_mode();
    let _ = execute!(terminal.backend_mut(), LeaveAlternateScreen);
    let _ = terminal.show_cursor();
    result
}

fn wizard(terminal: &mut Terminal<CrosstermBackend<Stderr>>) -> Option<Choice> {
    let mut step = 0usize; // 0 = posição, 1 = cor
    let mut pos = 1usize; // padrão: centro
    let mut theme = 0usize; // padrão: sage

    loop {
        terminal.draw(|f| draw(f, step, pos, theme)).ok()?;

        if let Event::Key(k) = event::read().ok()? {
            if k.kind != KeyEventKind::Press {
                continue;
            }
            let idx = if step == 0 { &mut pos } else { &mut theme };
            match k.code {
                KeyCode::Up | KeyCode::Char('k') => *idx = idx.saturating_sub(1),
                KeyCode::Down | KeyCode::Char('j') => *idx = (*idx + 1).min(2),
                KeyCode::Left | KeyCode::Backspace if step == 1 => step = 0,
                KeyCode::Enter | KeyCode::Right => {
                    if step == 0 {
                        step = 1;
                    } else {
                        return Some(Choice {
                            position: POSITIONS[pos].0,
                            theme: THEMES[theme].0,
                        });
                    }
                }
                KeyCode::Esc | KeyCode::Char('q') => return None,
                _ => {}
            }
        }
    }
}

fn draw(f: &mut Frame, step: usize, pos: usize, theme: usize) {
    let area = centered(f.area(), 60, 13);
    let rows = Layout::vertical([
        Constraint::Length(3), // título
        Constraint::Min(5),    // lista
        Constraint::Length(1), // rodapé
    ])
    .split(area);

    let title = Paragraph::new(Span::styled(
        "🍅 Configurar pomodoro",
        Style::default().add_modifier(Modifier::BOLD),
    ))
    .alignment(Alignment::Center)
    .block(Block::default().borders(Borders::ALL));
    f.render_widget(title, rows[0]);

    let (question, items): (String, Vec<ListItem>) = if step == 0 {
        (
            " Onde colocar o pomodoro na waybar?  (1/2) ".into(),
            POSITIONS.iter().map(|(_, label)| ListItem::new(*label)).collect(),
        )
    } else {
        (
            " Qual cor?  (2/2) ".into(),
            THEMES
                .iter()
                .map(|(_, label, color)| {
                    ListItem::new(Span::styled(*label, Style::default().fg(*color)))
                })
                .collect(),
        )
    };

    let mut state = ListState::default();
    state.select(Some(if step == 0 { pos } else { theme }));
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(question))
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol("➜ ");
    f.render_stateful_widget(list, rows[1], &mut state);

    let footer = Paragraph::new("↑/↓ mover · Enter confirmar · Esc cancelar")
        .alignment(Alignment::Center)
        .style(Style::default().fg(Color::DarkGray));
    f.render_widget(footer, rows[2]);
}

/// Retângulo centralizado de `width`×`height` dentro de `area`.
fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let w = width.min(area.width);
    let h = height.min(area.height);
    Rect {
        x: area.x + (area.width.saturating_sub(w)) / 2,
        y: area.y + (area.height.saturating_sub(h)) / 2,
        width: w,
        height: h,
    }
}
