# Omadoro

Omadoro é o pomodoro do Omarchy, um timer que vive dentro da omarchy-shell.
Este glossário fixa os nomes que o código, os testes e os documentos usam
para falar do timer.

## Language

**Fase**:
Um trecho contínuo do ciclo com duração própria. Há três: Foco, Pausa e Pausa
longa.
_Avoid_: etapa, período, sessão

**Foco**:
A fase de trabalho. Só um Foco que termina sozinho conta para a cadência da
Pausa longa.
_Avoid_: work, trabalho, pomodoro (como fase)

**Pausa**:
A fase curta de descanso que vem depois de um Foco.
_Avoid_: break, intervalo, descanso

**Pausa longa**:
A pausa maior que substitui a Pausa a cada N Focos concluídos.
_Avoid_: long break, pausa grande

**Ciclo**:
A contagem de Focos concluídos desde o último zerar. Decide quando vem a
Pausa longa.
_Avoid_: rodada, série, sprint

**Foco concluído**:
Um Foco que chegou ao fim pelo relógio. Entra no Ciclo.
_Avoid_: foco feito, foco terminado

**Foco pulado**:
Um Foco encerrado pelo botão de pular. Não entra no Ciclo.
_Avoid_: foco cancelado, foco abortado

**Relógio**:
O estado de tempo do timer. Ou está rodando, e guarda o instante de fim, ou
está pausado, e guarda quanto falta. Nunca os dois.
_Avoid_: contador, cronômetro, countdown

**Instante de fim**:
O momento absoluto em que a Fase termina, quando o Relógio está rodando.
_Avoid_: end, deadline, tempo final

**Restante**:
Quanto falta para a Fase terminar. Derivado do Instante de fim quando rodando,
guardado quando pausado.
_Avoid_: remaining, tempo que sobra

**Buraco**:
Um intervalo sem ticks maior que o limite de suspensão. Indica que a máquina
dormiu ou a shell caiu. Rebobina a Fase cheia e pausada, sem aviso.
_Avoid_: gap, lacuna, salto

**Batida**:
A gravação periódica do último instante visto, só para detectar Buraco depois
de um reinício.
_Avoid_: heartbeat, keepalive

**Resincronização**:
Ajuste do Restante quando uma duração muda e a Fase está pausada ainda no
tempo cheio. Fases rodando ou no meio não mudam.
_Avoid_: resync, atualização de duração

**Evento**:
Um pedido de mudança ao redutor: tick, alternar, iniciar, pular, reiniciar,
zerar ou nova configuração.
_Avoid_: ação, comando, mensagem

**Efeito**:
Uma consequência que o redutor pede e o Service executa: gravar, notificar ou
tocar som.
_Avoid_: side effect, callback

**Chip**:
O item do plugin na barra: anel mais MM:SS.
_Avoid_: widget da barra, ícone, módulo

**Popup**:
A janela ancorada no Chip com as abas Pomodoro e Config.
_Avoid_: painel, janela, modal

**Entrada inline**:
O objeto do plugin dentro do layout da barra em `shell.json`, onde a
configuração do usuário fica.
_Avoid_: settings, config do widget

**Estado de execução**:
Fase, Relógio, Ciclo e Batida, gravados em arquivo próprio. Nunca vai para a
Entrada inline.
_Avoid_: state, runtime state
