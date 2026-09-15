---
status: accepted
---

# SystemClock sempre ativo, precisão ligada a um bool plano

A notificação de fim de fase é o produto e tem de disparar com o Popup
fechado, então o Service tica sempre, com um `SystemClock` que segue o
relógio de parede e se corrige depois de um suspend. A precisão cai para
minutos quando o timer está parado. Decidimos ligar essa precisão a um
`property bool running` escrito em `adopt`, e não a `view.running` nem a
`timer.clock.state`. As duas formas derivadas fecham um laço de binding que
a shell loga como "Binding loop detected", medido ao vivo nas duas. O bool
duplica um dado que o modelo diz ser derivado, e isso é deliberado.

## Consequences

- Parado, o relógio só bate por minuto. Todo Evento do usuário refresca
  `nowMs` antes do redutor, senão a Fase nova encurta em até 59 segundos.
