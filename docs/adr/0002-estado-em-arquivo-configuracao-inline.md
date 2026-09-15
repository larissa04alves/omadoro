---
status: accepted
---

# Estado de execução em arquivo próprio, configuração inline no shell.json

O Estado de execução muda a cada 30 segundos enquanto o timer roda. A
configuração do usuário muda algumas vezes por semana. Decidimos separar por
dono e cadência: o Estado vai para `$XDG_STATE_HOME/<id>/state.json` por
`FileView` com escrita atômica, e as durações ficam na Entrada inline do
plugin em `shell.json`, escritas só por `updateEntryInline`. Um único arquivo
para tudo obrigaria a reescrever o layout da barra do usuário a cada Batida,
e um segundo arquivo de configuração criaria uma segunda verdade ao lado da
que `omarchy bar set` lê.

## Consequences

- Trocar o id do plugin muda a pasta do Estado. O timer recomeça pausado.
- O Service lê a configuração pela fachada do host e nunca a copia
  localmente.
