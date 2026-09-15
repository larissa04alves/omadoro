---
status: accepted
---

# Um IpcHandler, no Service; o Popup não registra alvo IPC

`Ui/Panel` oferece um alvo IPC de graça, mas o Popup existe uma vez por
monitor. Com dois monitores o mesmo alvo seria registrado duas vezes e a
shell descartaria um deles. Decidimos que o único `IpcHandler` mora no
Service, que é singleton, com `manageIpc: false` no Popup. Os verbos de
janela (`open`, `close`, `toggle`) voltam pelo `shell.summon`, `shell.hide` e
`shell.toggle` do próprio plugin, que roteiam pelo monitor certo. É o mesmo
arranjo do plugin Chime e de nove painéis de primeira parte da shell.
