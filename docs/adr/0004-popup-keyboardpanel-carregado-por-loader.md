---
status: accepted
---

# Popup com raiz Ui/Panel e KeyboardPanel aninhado, carregado por Loader

O BarWidget carrega o Popup por um `Loader`, e um `Loader` não preenche
propriedades `required`. `KeyboardPanel` declara `anchorItem` e `bar` como
`required`, então não pode ser a raiz. Decidimos que a raiz de `Panel.qml` é
um `Ui/Panel` sem propriedades obrigatórias, com o `KeyboardPanel` aninhado
dentro, e o BarWidget injeta `bar`, `service`, `anchorItem` e `hostWidget`
depois do `onLoaded`, testando `"nome" in alvo`. Escolhemos `KeyboardPanel` e
não `PopupCard` porque `Esc` só chega pelo `PanelKeyCatcher`, que precisa de
foco, e `PopupCard` não tem foco nenhum.

## Consequences

- `switchPanel` precisa de override para passar o widget do slot ao host,
  senão `Tab` dentro do Popup não faz nada.
- Salvar `Panel.qml` pode servir uma cópia antiga até a shell reiniciar.
