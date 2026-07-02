//! CLI `pomo`. Cada subcomando é fino: carrega config/estado, delega para a
//! lib e persiste. `tick` (waybar) e `get` (eww) imprimem JSON.

use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use clap::{Parser, Subcommand};
use pomo::config::Config;
use pomo::render::{eww_json, waybar_json};
use pomo::state::{State, Transition};

#[derive(Parser)]
#[command(name = "pomo", about = "Timer pomodoro para waybar/eww")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Heartbeat da waybar: avança o tempo e imprime o JSON da barra.
    Tick,
    /// Leitura para o eww: imprime o JSON do popup.
    Get,
    /// Alterna entre rodando e pausado.
    Toggle,
    /// Pula para a próxima fase.
    Skip,
    /// Reinicia a fase atual.
    Restart,
    /// Zera o ciclo.
    Reset,
    /// Ajusta a config: `pomo config set <chave> <valor>`.
    Config {
        #[command(subcommand)]
        action: ConfigCmd,
    },
    /// TUI de configuração; imprime "posição tema" no stdout.
    Configure,
}

#[derive(Subcommand)]
enum ConfigCmd {
    Set { key: String, value: String },
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn main() {
    let cli = Cli::parse();
    let cfg = Config::load();

    match cli.cmd {
        Cmd::Tick => {
            let t_now = now();
            let mut state = State::load(&cfg);
            if let Some(transition) = state.tick(t_now, &cfg) {
                let _ = state.save();
                notify(transition);
            }
            println!("{}", waybar_json(&state, t_now, &cfg));
        }
        Cmd::Get => {
            let state = State::load(&cfg);
            println!("{}", eww_json(&state, now(), &cfg));
        }
        Cmd::Toggle => mutate(&cfg, |s| s.toggle(now())),
        Cmd::Skip => mutate(&cfg, |s| s.skip(now(), &cfg)),
        Cmd::Restart => mutate(&cfg, |s| s.restart(now(), &cfg)),
        Cmd::Reset => mutate(&cfg, |s| s.reset(&cfg)),
        Cmd::Config { action } => {
            let ConfigCmd::Set { key, value } = action;
            let mut updated = cfg.clone();
            if let Err(e) = updated.set(&key, &value) {
                eprintln!("pomo: {e}");
                std::process::exit(1);
            }
            // Reflete a nova duração no timer atual, se estiver pausado no início.
            let mut state = State::load(&cfg);
            if state.resync_duration(&cfg, &updated) {
                let _ = state.save();
            }
            if let Err(e) = updated.save() {
                eprintln!("pomo: falha ao salvar config: {e}");
                std::process::exit(1);
            }
        }
        Cmd::Configure => match pomo::configure::run() {
            Some(c) => println!("{} {}", c.position, c.theme),
            None => std::process::exit(1),
        },
    }
}

/// Carrega o estado, aplica `f`, salva.
fn mutate(cfg: &Config, f: impl FnOnce(&mut State)) {
    let mut state = State::load(cfg);
    f(&mut state);
    if let Err(e) = state.save() {
        eprintln!("pomo: falha ao salvar estado: {e}");
        std::process::exit(1);
    }
}

/// Notificação + som ao trocar de fase. Os filhos são desacoplados do stdout
/// (a waybar lê o stdout do `tick`) e sobrevivem ao término deste processo.
fn notify(t: Transition) {
    let body = format!("{} terminou — {} agora", t.ended.label(), t.started.label());
    spawn(Command::new("notify-send").args(["-a", "Pomodoro", "Pomodoro", &body]));
    play_sound();
}

fn play_sound() {
    if spawn(Command::new("canberra-gtk-play").args(["-i", "complete"])) {
        return;
    }
    spawn(Command::new("paplay").arg("/usr/share/sounds/freedesktop/stereo/complete.oga"));
}

/// Dispara um comando em background, silenciando I/O. Retorna true se iniciou.
fn spawn(cmd: &mut Command) -> bool {
    cmd.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .is_ok()
}
