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

/// Um buraco entre ticks maior que isto significa que o PC esteve
/// desligado/suspenso: a fase volta ao tempo cheio, pausada.
const GAP_SECS: u64 = 120;
/// Cadência de persistência do heartbeat (`last_tick`) enquanto roda.
const PERSIST_EVERY: u64 = 30;
/// Teto de sanidade para `remaining` vindo do disco.
const MAX_REMAINING: u64 = 24 * 3600;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct State {
    #[serde(default)]
    pub phase: Phase,
    #[serde(default)]
    pub running: bool,
    /// Epoch (segundos) em que a fase termina, quando `running`.
    #[serde(default)]
    pub end: u64,
    /// Segundos restantes, usado quando pausado.
    #[serde(default)]
    pub remaining: u64,
    /// Focos concluídos no ciclo atual (para a cadência da pausa longa).
    #[serde(default)]
    pub completed_work: u64,
    /// Último tick visto (epoch), persistido a cada [`PERSIST_EVERY`] enquanto
    /// roda. Serve só para detectar desligamento/suspend ([`GAP_SECS`]).
    #[serde(default)]
    pub last_tick: u64,
}

/// Transição de fase, devolvida por [`State::tick`] para disparar notificação/som.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Transition {
    pub ended: Phase,
    pub started: Phase,
}

/// Resultado de um tick: a eventual transição de fase e se o estado mudou
/// (e portanto precisa ser salvo).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TickResult {
    pub transition: Option<Transition>,
    pub dirty: bool,
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
            last_tick: 0,
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
            Ok(s) => serde_json::from_str(&s)
                .map(|mut st: State| {
                    // Sanidade contra arquivo editado/corrompido.
                    st.remaining = st.remaining.min(MAX_REMAINING);
                    st
                })
                .unwrap_or_else(|_| State::initial(cfg)),
            Err(_) => State::initial(cfg),
        }
    }

    /// Grava de forma atômica (tmp + rename) para não corromper em leitura
    /// concorrente. O tmp leva o PID no nome: waybar (tick), eww (get) e os
    /// botões do popup rodam processos `pomo` simultâneos. Trade-off aceito:
    /// um kill -9 entre write e rename deixa um tmp órfão inofensivo para trás.
    pub fn save(&self) -> std::io::Result<()> {
        let p = State::path();
        if let Some(dir) = p.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = p.with_extension(format!("json.tmp.{}", std::process::id()));
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
            self.end = now.saturating_add(self.remaining);
            self.running = true;
            self.last_tick = now;
        }
    }

    /// Reinicia a fase atual para o tempo cheio (botão ↺).
    pub fn restart(&mut self, now: u64, cfg: &Config) {
        self.remaining = duration_secs(self.phase, cfg);
        if self.running {
            self.end = now.saturating_add(self.remaining);
            self.last_tick = now;
        }
    }

    /// Pula manualmente para a próxima fase e a inicia (botão ⏭). Um foco
    /// pulado NÃO conta para a cadência da pausa longa (pomodoro pulado não é
    /// pomodoro feito).
    pub fn skip(&mut self, now: u64, cfg: &Config) {
        self.advance(now, cfg, true, false);
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

    /// Chamado a cada segundo pela waybar. Detecta desligamento/suspend (buraco
    /// entre ticks), avança a fase quando ela termina e mantém o heartbeat.
    /// `dirty` indica que o chamador deve persistir o estado.
    pub fn tick(&mut self, now: u64, cfg: &Config) -> TickResult {
        if !self.running {
            return TickResult { transition: None, dirty: false };
        }
        // PC desligado/suspenso no meio da fase (buraco entre ticks) ou estado
        // corrompido (`end` mais distante do que qualquer fase legítima): volta
        // ao tempo cheio, pausado, sem notificação.
        let gap = self.last_tick > 0 && now.saturating_sub(self.last_tick) > GAP_SECS;
        let end_absurdo = self.end.saturating_sub(now) > MAX_REMAINING;
        if gap || end_absurdo {
            self.remaining = duration_secs(self.phase, cfg);
            self.running = false;
            self.end = 0;
            self.last_tick = 0;
            return TickResult { transition: None, dirty: true };
        }
        if now >= self.end {
            let t = self.advance(now, cfg, cfg.auto_start_next, true);
            return TickResult { transition: Some(t), dirty: true };
        }
        // Heartbeat: persiste o último tick de tempos em tempos (não a cada
        // segundo) só para a detecção de gap acima.
        if now.saturating_sub(self.last_tick) >= PERSIST_EVERY {
            self.last_tick = now;
            return TickResult { transition: None, dirty: true };
        }
        TickResult { transition: None, dirty: false }
    }

    /// Avança para a próxima fase. `start_running` decide se ela já começa a
    /// contar; `count_work` decide se um foco encerrado entra na cadência da
    /// pausa longa (true no fim natural, false no skip).
    fn advance(&mut self, now: u64, cfg: &Config, start_running: bool, count_work: bool) -> Transition {
        let ended = self.phase;
        if ended.is_work() && count_work {
            self.completed_work += 1;
        }
        let started = next_phase(ended, self.completed_work, cfg.long_every);
        self.phase = started;
        self.remaining = duration_secs(started, cfg);
        self.running = start_running;
        self.end = if start_running { now.saturating_add(self.remaining) } else { 0 };
        self.last_tick = if start_running { now } else { 0 };
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
        assert_eq!(s.tick(1499, &c).transition, None);
        let t = s.tick(1500, &c).transition.unwrap();
        assert_eq!(t.ended, Phase::Work);
        assert_eq!(t.started, Phase::ShortBreak);
        assert_eq!(s.completed_work, 1);
        // auto_start_next=false por padrão → pausado, não re-dispara
        assert!(!s.running);
        assert_eq!(s.tick(2000, &c), TickResult { transition: None, dirty: false });
    }

    #[test]
    fn full_cycle_hits_long_break() {
        let mut c = cfg();
        c.auto_start_next = true; // encadeia as fases sozinho
        let mut s = State::initial(&c);
        s.toggle(0);
        let mut long_seen = false;
        for _ in 0..12 {
            let now = s.end; // salta para o fim da fase corrente…
            s.last_tick = now - 1; // …simulando que a waybar ticou até lá
            if let Some(t) = s.tick(now, &c).transition {
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
        // foco pulado não conta para a cadência da pausa longa
        assert_eq!(s.completed_work, 0);
    }

    #[test]
    fn skipped_work_never_earns_long_break() {
        let c = cfg(); // long_every = 4
        let mut s = State::initial(&c);
        for _ in 0..10 {
            s.skip(1000, &c); // pula tudo, nunca completa um foco
            assert_ne!(s.phase, Phase::LongBreak);
        }
        assert_eq!(s.completed_work, 0);
    }

    #[test]
    fn gap_resets_phase_paused_without_transition() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(1000); // rodando, end=2500
        assert!(s.tick(1030, &c).dirty); // heartbeat: last_tick=1030
        // "religou o PC" 10h depois: fase cheia, pausada, sem notificação
        let r = s.tick(1030 + 36_000, &c);
        assert_eq!(r.transition, None);
        assert!(r.dirty);
        assert!(!s.running);
        assert_eq!(s.remaining, 25 * 60);
        assert_eq!(s.end, 0);
    }

    #[test]
    fn short_gap_does_not_reset() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(1000);
        assert!(s.tick(1030, &c).dirty); // last_tick=1030
        let r = s.tick(1090, &c); // 60s de buraco: dentro da tolerância
        assert_eq!(r.transition, None);
        assert!(s.running);
    }

    #[test]
    fn heartbeat_persists_periodically_not_every_tick() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(1000); // last_tick=1000
        assert!(!s.tick(1001, &c).dirty);
        assert!(!s.tick(1029, &c).dirty);
        assert!(s.tick(1030, &c).dirty); // 30s desde o último registro
        assert!(!s.tick(1031, &c).dirty);
    }

    #[test]
    fn paused_state_never_dirties_on_tick() {
        let c = cfg();
        let mut s = State::initial(&c);
        assert_eq!(s.tick(999_999, &c), TickResult { transition: None, dirty: false });
    }

    #[test]
    fn absurd_end_resets_phase_paused() {
        let c = cfg();
        let mut s = State::initial(&c);
        s.toggle(1000);
        s.end = 1000 + 200 * 3600; // state.json corrompido: fim daqui a 200h
        let r = s.tick(1001, &c);
        assert_eq!(r.transition, None);
        assert!(r.dirty);
        assert!(!s.running);
        assert_eq!(s.remaining, 25 * 60);
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
