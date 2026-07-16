//! Formatação da saída: texto da barra (waybar) e dados do popup (eww).

use crate::config::Config;
use crate::state::State;

/// Glifos de círculo de progresso (nerd font), do vazio ao cheio.
const RING_GLYPHS: [&str; 8] = ["󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥"];

/// "MM:SS" a partir de segundos.
pub fn mmss(secs: u64) -> String {
    format!("{:02}:{:02}", secs / 60, secs % 60)
}

/// Glifo do anel para um progresso 0.0..=1.0.
pub fn glyph_for(progress: f64) -> &'static str {
    let last = RING_GLYPHS.len() - 1;
    let idx = (progress.clamp(0.0, 1.0) * last as f64).round() as usize;
    RING_GLYPHS[idx.min(last)]
}

/// Classe CSS do módulo da barra conforme o estado.
fn bar_class(state: &State) -> &'static str {
    if !state.running {
        "paused"
    } else if state.phase.is_work() {
        "focus"
    } else {
        "break"
    }
}

/// JSON consumido pela waybar (`return-type: json`).
pub fn waybar_json(state: &State, now: u64, cfg: &Config) -> String {
    let progress = state.progress(now, cfg);
    let text = format!("{} {}", glyph_for(progress), mmss(state.remaining(now)));
    let done_in_cycle = if cfg.long_every > 0 { state.completed_work % cfg.long_every } else { 0 };
    let tooltip = format!(
        "{} — {} · {} restante · {}/{} focos até a pausa longa",
        state.phase.label(),
        if state.running { "em andamento" } else { "pausado" },
        mmss(state.remaining(now)),
        done_in_cycle,
        cfg.long_every,
    );
    serde_json::json!({
        "text": text,
        "class": bar_class(state),
        "percentage": (progress * 100.0).round() as u64,
        "tooltip": tooltip,
    })
    .to_string()
}

/// JSON consumido pelo eww (campos acessados como `{estado.campo}` no yuck).
/// Inclui o estado do timer e a config, para os sliders da aba Config.
pub fn eww_json(state: &State, now: u64, cfg: &Config) -> String {
    serde_json::json!({
        "mmss": mmss(state.remaining(now)),
        // O circular-progress do eww espera 0–100, não a fração 0.0–1.0 de
        // State::progress — não "simplificar" removendo o ×100.
        "percent": (state.progress(now, cfg) * 100.0).round() as u64,
        "phase": state.phase.key(),
        "phase_label": state.phase.label(),
        "running": state.running,
        "work": cfg.work,
        "short": cfg.short,
        "long": cfg.long,
        "long_every": cfg.long_every,
        "auto_start_next": cfg.auto_start_next,
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mmss_formats() {
        assert_eq!(mmss(0), "00:00");
        assert_eq!(mmss(65), "01:05");
        assert_eq!(mmss(25 * 60), "25:00");
        assert_eq!(mmss(59), "00:59");
    }

    #[test]
    fn glyph_extremes() {
        assert_eq!(glyph_for(0.0), RING_GLYPHS[0]);
        assert_eq!(glyph_for(1.0), RING_GLYPHS[7]);
        assert_eq!(glyph_for(-5.0), RING_GLYPHS[0]);
        assert_eq!(glyph_for(2.0), RING_GLYPHS[7]);
    }

    #[test]
    fn waybar_json_has_fields() {
        let c = Config::default();
        let s = State::initial(&c);
        let j: serde_json::Value = serde_json::from_str(&waybar_json(&s, 0, &c)).unwrap();
        assert!(j["text"].as_str().unwrap().contains("25:00"));
        assert_eq!(j["class"], "paused");
        assert_eq!(j["percentage"], 100);
    }

    #[test]
    fn eww_json_has_fields() {
        let c = Config::default();
        let s = State::initial(&c);
        let j: serde_json::Value = serde_json::from_str(&eww_json(&s, 0, &c)).unwrap();
        assert_eq!(j["phase"], "work");
        assert_eq!(j["phase_label"], "Foco");
        assert_eq!(j["running"], false);
    }
}
