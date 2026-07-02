//! Fases do ciclo pomodoro e a lógica de transição entre elas.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Work,
    ShortBreak,
    LongBreak,
}

impl Phase {
    /// Rótulo em PT exibido na UI.
    pub fn label(self) -> &'static str {
        match self {
            Phase::Work => "Foco",
            Phase::ShortBreak => "Pausa",
            Phase::LongBreak => "Pausa longa",
        }
    }

    /// Chave curta usada no JSON (barra/eww) e no CSS.
    pub fn key(self) -> &'static str {
        match self {
            Phase::Work => "work",
            Phase::ShortBreak => "short_break",
            Phase::LongBreak => "long_break",
        }
    }

    pub fn is_work(self) -> bool {
        matches!(self, Phase::Work)
    }
}

/// Decide a próxima fase.
///
/// `completed_work` = total de focos concluídos (contando o que acabou de terminar).
/// Após cada foco vem uma pausa: longa a cada `long_every` focos, curta caso contrário.
/// Depois de qualquer pausa, volta ao foco.
pub fn next_phase(current: Phase, completed_work: u64, long_every: u64) -> Phase {
    match current {
        Phase::Work => {
            if long_every > 0 && completed_work.is_multiple_of(long_every) {
                Phase::LongBreak
            } else {
                Phase::ShortBreak
            }
        }
        Phase::ShortBreak | Phase::LongBreak => Phase::Work,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn work_then_short_break() {
        assert_eq!(next_phase(Phase::Work, 1, 4), Phase::ShortBreak);
        assert_eq!(next_phase(Phase::Work, 2, 4), Phase::ShortBreak);
        assert_eq!(next_phase(Phase::Work, 3, 4), Phase::ShortBreak);
    }

    #[test]
    fn long_break_every_n() {
        assert_eq!(next_phase(Phase::Work, 4, 4), Phase::LongBreak);
        assert_eq!(next_phase(Phase::Work, 8, 4), Phase::LongBreak);
    }

    #[test]
    fn break_returns_to_work() {
        assert_eq!(next_phase(Phase::ShortBreak, 4, 4), Phase::Work);
        assert_eq!(next_phase(Phase::LongBreak, 4, 4), Phase::Work);
    }
}
