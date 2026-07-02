//! Estado de execução do timer.
//!
//! A "sacada": guardamos o timestamp de fim da fase, então "quanto falta" é só
//! `end - agora` — não há processo contando segundos. Quem tica é a waybar,
//! chamando `pomo tick` a cada segundo.

use crate::config::Config;
use crate::phase::{next_phase, Phase};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct State {
    pub phase: Phase,
    pub running: bool,
    /// Epoch (segundos) em que a fase termina, quando `running`.
    pub end: u64,
    /// Segundos restantes, usado quando pausado.
    pub remaining: u64,
    /// Focos concluídos no ciclo atual (para a cadência da pausa longa).
    pub completed_work: u64,
}

/// Transição de fase, devolvida por [`State::tick`] para disparar notificação/som.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Transition {
    pub ended: Phase,
    pub started: Phase,
}

impl State {
    /// Estado inicial: foco pausado no tempo cheio.
    pub fn initial(cfg: &Config) -> State {
        State {
            phase: Phase::Work,
            running: false,
            end: 0,
            remaining: duration_secs(Phase::Work, cfg),
            completed_work: 0,
        }
    }

    /// Caminho do arquivo (`~/.local/state/pomodoro/state.json`).
    pub fn path() -> PathBuf {
        dirs::state_dir()
            .or_else(dirs::data_local_dir)
            .unwrap_or_else(|| PathBuf::from("."))
            .join("pomodoro")
            .join("state.json")
    }

    pub fn load(cfg: &Config) -> State {
        match fs::read_to_string(State::path()) {
            Ok(s) => serde_json::from_str(&s).unwrap_or_else(|_| State::initial(cfg)),
            Err(_) => State::initial(cfg),
        }
    }

    /// Grava de forma atômica (tmp + rename) para não corromper em leitura concorrente.
    pub fn save(&self) -> std::io::Result<()> {
        let p = State::path();
        if let Some(dir) = p.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = p.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_string_pretty(self).unwrap())?;
        fs::rename(tmp, p)
    }

    /// Segundos restantes no instante `now`.
    pub fn remaining(&self, now: u64) -> u64 {
        if self.running {
            self.end.saturating_sub(now)
        } else {
            self.remaining
        }
    }

    /// Progresso 0.0..=1.0 (cheio → vazio conforme o tempo passa).
    pub fn progress(&self, now: u64, cfg: &Config) -> f64 {
        let total = duration_secs(self.phase, cfg);
        if total == 0 {
            return 0.0;
        }
        (self.remaining(now) as f64 / total as f64).clamp(0.0, 1.0)
    }

    /// Alterna entre rodando e pausado.
    pub fn toggle(&mut self, now: u64) {
        if self.running {
            self.remaining = self.remaining(now);
            self.running = false;
            self.end = 0;
        } else {
            self.end = now + self.remaining;
            self.running = true;
        }
    }

    /// Reinicia a fase atual para o tempo cheio (botão ↺).
    pub fn restart(&mut self, now: u64, cfg: &Config) {
        self.remaining = duration_secs(self.phase, cfg);
        if self.running {
            self.end = now + self.remaining;
        }
    }

    /// Pula manualmente para a próxima fase e a inicia (botão ⏭).
    pub fn skip(&mut self, now: u64, cfg: &Config) {
        self.advance(now, cfg, true);
    }

    /// Zera o ciclo: foco pausado no tempo cheio.
    pub fn reset(&mut self, cfg: &Config) {
        *self = State::initial(cfg);
    }

    /// Reflete uma mudança de config no tempo restante: se a fase atual está
    /// pausada e cheia (ainda não começou a correr), passa a mostrar a nova
    /// duração no ato. Fases rodando ou pausadas no meio não são tocadas
    /// (a mudança vale no próximo ciclo). Retorna `true` se alterou o estado.
    pub fn resync_duration(&mut self, old: &Config, new: &Config) -> bool {
        if !self.running && self.remaining == duration_secs(self.phase, old) {
            let updated = duration_secs(self.phase, new);
            if updated != self.remaining {
                self.remaining = updated;
                return true;
            }
        }
        false
    }

    /// Chamado a cada segundo pela waybar. Se a fase terminou, avança e devolve
    /// a transição (para notificação); caso contrário devolve `None`.
    pub fn tick(&mut self, now: u64, cfg: &Config) -> Option<Transition> {
        if self.running && now >= self.end {
            Some(self.advance(now, cfg, cfg.auto_start_next))
        } else {
            None
        }
    }

    /// Avança para a próxima fase. `start_running` decide se ela já começa a contar.
    fn advance(&mut self, now: u64, cfg: &Config, start_running: bool) -> Transition {
        let ended = self.phase;
        if ended.is_work() {
            self.completed_work += 1;
        }
        let started = next_phase(ended, self.completed_work, cfg.long_every);
        self.phase = started;
        self.remaining = duration_secs(started, cfg);
        self.running = start_running;
        self.end = if start_running { now + self.remaining } else { 0 };
        Transition { ended, started }
    }
}

/// Duração de uma fase em segundos, a partir da config (em minutos).
pub fn duration_secs(phase: Phase, cfg: &Config) -> u64 {
    let minutes = match phase {
        Phase::Work => cfg.work,
        Phase::ShortBreak => cfg.short,
        Phase::LongBreak => cfg.long,
    };
    minutes * 60
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> Config {
        Config::default()
    }

    #[test]
    fn remaining_running_vs_paused() {
        let c = cfg();
        let mut s = State::initial(&c); // 25min, pausado
        assert_eq!(s.remaining(1000), 25 * 60);
        s.toggle(1000); // inicia em now=1000 → end=1000+1500
        assert_eq!(s.end, 1000 + 1500);
        assert_eq!(s.remaining(1000), 1500);
        assert_eq!(s.remaining(1100), 1400);
    }

    #[test]
    fn remaining_clamps_at_zero() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(0);
        assert_eq!(s.remaining(999_999), 0);
    }

    #[test]
    fn toggle_preserves_remaining_when_pausing() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(0); // rodando, end=1500
        s.toggle(100); // pausa em now=100 → remaining=1400
        assert!(!s.running);
        assert_eq!(s.remaining, 1400);
    }

    #[test]
    fn restart_resets_current_phase() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(0);
        s.restart(500, &c);
        assert_eq!(s.remaining(500), 1500);
    }

    #[test]
    fn tick_transitions_once_at_zero() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(0); // foco rodando, end=1500
        assert_eq!(s.tick(1499, &c), None);
        let t = s.tick(1500, &c).unwrap();
        assert_eq!(t.ended, Phase::Work);
        assert_eq!(t.started, Phase::ShortBreak);
        assert_eq!(s.completed_work, 1);
        // auto_start_next=false por padrão → pausado, não re-dispara
        assert!(!s.running);
        assert_eq!(s.tick(2000, &c), None);
    }

    #[test]
    fn full_cycle_hits_long_break() {
        let mut c = cfg();
        c.auto_start_next = true; // encadeia as fases sozinho
        let mut s = State::initial(&c);
        s.toggle(0);
        let mut long_seen = false;
        for _ in 0..12 {
            let now = s.end; // salta para o fim da fase corrente
            if let Some(t) = s.tick(now, &c) {
                if t.started == Phase::LongBreak {
                    long_seen = true;
                    break;
                }
            }
        }
        assert!(long_seen, "deveria atingir a pausa longa após {} focos", c.long_every);
        assert_eq!(s.completed_work, 4);
    }

    #[test]
    fn skip_advances_and_runs() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.skip(0, &c);
        assert_eq!(s.phase, Phase::ShortBreak);
        assert!(s.running);
        assert_eq!(s.remaining(0), 5 * 60);
    }

    #[test]
    fn reset_returns_to_initial() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.skip(0, &c);
        s.skip(0, &c);
        s.reset(&c);
        assert_eq!(s, State::initial(&c));
    }

    #[test]
    fn resync_snaps_paused_full_phase() {
        let old = cfg();
        let mut new = old.clone();
        new.work = 40;
        let mut s = State::initial(&old); // foco pausado, 25:00
        assert!(s.resync_duration(&old, &new));
        assert_eq!(s.remaining, 40 * 60);
    }

    #[test]
    fn resync_skips_running_or_midphase() {
        let old = cfg();
        let mut new = old.clone();
        new.work = 40;

        let mut running = State::initial(&old);
        running.toggle(0); // rodando → não mexe
        assert!(!running.resync_duration(&old, &new));

        let mut mid = State::initial(&old);
        mid.remaining = 600; // pausado no meio → não mexe
        assert!(!mid.resync_duration(&old, &new));
        assert_eq!(mid.remaining, 600);
    }
}
