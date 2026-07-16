//! Configuração persistente (durações e comportamento).
//! Lida de `~/.config/pomodoro/config.json`; usa defaults se ausente/inválida.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Config {
    /// Duração do foco, em minutos.
    pub work: u64,
    /// Pausa curta, em minutos.
    pub short: u64,
    /// Pausa longa, em minutos.
    pub long: u64,
    /// A cada quantos focos vem uma pausa longa.
    pub long_every: u64,
    /// Iniciar a próxima fase automaticamente ao terminar a atual.
    pub auto_start_next: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config { work: 25, short: 5, long: 15, long_every: 4, auto_start_next: false }
    }
}

impl Config {
    /// Caminho do arquivo (`~/.config/pomodoro/config.json`).
    pub fn path() -> PathBuf {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("pomodoro")
            .join("config.json")
    }

    /// Carrega do disco; retorna defaults se o arquivo não existir ou for inválido.
    pub fn load() -> Config {
        match fs::read_to_string(Config::path()) {
            Ok(s) => serde_json::from_str(&s).unwrap_or_default(),
            Err(_) => Config::default(),
        }
    }

    /// Persiste no disco (cria o diretório se necessário) de forma atômica
    /// (tmp + rename): o slider do popup dispara escritas em rajada enquanto
    /// `pomo get`/`tick` leem concorrentemente — uma leitura de arquivo
    /// truncado cairia silenciosamente nos defaults.
    pub fn save(&self) -> std::io::Result<()> {
        let p = Config::path();
        if let Some(dir) = p.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = p.with_extension(format!("json.tmp.{}", std::process::id()));
        fs::write(&tmp, serde_json::to_string_pretty(self).unwrap())?;
        fs::rename(tmp, p)
    }

    /// Ajusta um campo por nome (usado por `pomo config set <chave> <valor>`).
    pub fn set(&mut self, key: &str, value: &str) -> Result<(), String> {
        match key {
            "work" => self.work = parse_minutes(value)?,
            "short" => self.short = parse_minutes(value)?,
            "long" => self.long = parse_minutes(value)?,
            "long_every" => {
                let n: u64 = value.parse().map_err(|_| format!("valor inválido: {value}"))?;
                if n == 0 {
                    return Err("long_every deve ser >= 1".into());
                }
                self.long_every = n;
            }
            "auto_start_next" => {
                self.auto_start_next = matches!(value, "true" | "1" | "on" | "yes");
            }
            other => return Err(format!("chave desconhecida: {other}")),
        }
        Ok(())
    }
}

fn parse_minutes(value: &str) -> Result<u64, String> {
    let n: u64 = value.parse().map_err(|_| format!("valor inválido: {value}"))?;
    if n == 0 {
        return Err("duração deve ser >= 1 minuto".into());
    }
    // Sem teto, um valor absurdo vira um `end` que o tick nunca alcança
    // (timer "rodando" para sempre).
    if n > 24 * 60 {
        return Err("duração deve ser <= 1440 minutos (24h)".into());
    }
    Ok(n)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_25_5_15_4() {
        let c = Config::default();
        assert_eq!((c.work, c.short, c.long, c.long_every), (25, 5, 15, 4));
        assert!(!c.auto_start_next);
    }

    #[test]
    fn roundtrip_serde() {
        let c = Config { work: 30, short: 8, long: 20, long_every: 3, auto_start_next: true };
        let back: Config = serde_json::from_str(&serde_json::to_string(&c).unwrap()).unwrap();
        assert_eq!(c, back);
    }

    #[test]
    fn set_valid_fields() {
        let mut c = Config::default();
        c.set("work", "40").unwrap();
        c.set("auto_start_next", "true").unwrap();
        assert_eq!(c.work, 40);
        assert!(c.auto_start_next);
    }

    #[test]
    fn set_rejects_bad_input() {
        let mut c = Config::default();
        assert!(c.set("work", "0").is_err());
        assert!(c.set("work", "abc").is_err());
        assert!(c.set("work", "1441").is_err());
        assert!(c.set("work", "1440").is_ok());
        assert!(c.set("long_every", "0").is_err());
        assert!(c.set("chave_inexistente", "1").is_err());
    }
}
