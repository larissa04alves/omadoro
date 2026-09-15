---
status: accepted
---

# Plugin QML puro, sem binário Rust

O timer nasceu como CLI Rust sem daemon porque a Waybar não tem memória entre
ticks. A omarchy-shell é um processo residente que monta um Service por
plugin, então essa premissa caiu. Decidimos portar a máquina de estados para
`Model.js` e apagar o Rust. `omarchy plugin add` não tem passo de build, e um
binário teria de ser um blob commitado por arquitetura. Os 28 testes do
`cargo test` foram portados pelo mesmo nome para `test/model.test.js` antes
de qualquer QML existir, e são o oráculo do porte.

## Considered Options

- Manter o `pomo` como processo filho falado por stdout, como o agent-bar faz.
  Perde porque cria um segundo dono do estado e um formato de fio entre os
  dois.
- Chamar o `pomo` por `Process` a cada segundo. Perde por custo e por manter
  dois escritores no mesmo arquivo.
