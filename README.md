# Pomodoro para a barra do Omarchy

Timer pomodoro como plugin da omarchy-shell. Um anel de progresso com a
contagem regressiva fica na barra. O clique abre um popup com duas abas,
**Pomodoro** (anel, pausar, pular, reiniciar) e **Config** (durações e
auto-início).

Não há binário, não há daemon próprio e não há passo de build. O plugin roda
dentro da shell que você já usa, com a lógica em um arquivo JavaScript e a
view em QML.

## Instalar

Requer Omarchy 4 com a omarchy-shell como barra (testado em 4.0.3).

```bash
omarchy plugin add https://github.com/larissa04alves/pomodoro-timer.git --enable
```

O `--enable` pergunta em qual seção da barra colocar o widget. O padrão é
`right`. Para mover depois:

```bash
omarchy bar move othavi0.pomodoro --section center
```

## Usar

| Gesto | O que faz |
| --- | --- |
| Clique esquerdo na barra | Abre ou fecha o popup |
| Clique direito na barra | Pausa ou retoma sem abrir o popup |
| Clique do meio na barra | Reinicia a fase atual |
| `Esc` no popup | Fecha o popup |
| `Tab` no popup | Vai para o próximo painel da barra |
| Setas no popup | Trocam de aba |
| `Enter` ou `Espaço` no popup | Pausa ou retoma |

## Configurar

A aba **Config** do popup tem quatro sliders e um interruptor:

| Opção | Faixa |
| --- | --- |
| Foco | 5 a 60 minutos |
| Pausa curta | 1 a 20 minutos |
| Pausa longa | 10 a 45 minutos |
| Ciclos até a pausa longa | 2 a 8 |
| Auto-iniciar a próxima fase | ligado ou desligado |

As opções são gravadas inline na entrada do plugin em
`~/.config/omarchy/shell.json`, o mesmo arquivo que guarda o resto do layout
da barra. A entrada é editável à mão, ou pela CLI da barra:

```bash
omarchy bar set othavi0.pomodoro work 30
```

Formato da entrada:

```jsonc
{ "id": "othavi0.pomodoro", "work": 25, "short": 5, "long": 15,
  "longEvery": 4, "autoStartNext": false }
```

A chave `sound` aceita o caminho de um arquivo de áudio. Vazia, o plugin toca
`complete.oga` do freedesktop.

O estado de execução não fica aí. Fase, relógio e ciclo ficam em
`~/.local/state/othavi0.pomodoro/state.json`, ou sob `$XDG_STATE_HOME` se a
variável estiver definida.

## Atalhos

Os mesmos verbos que o popup usa estão no IPC da shell:

```bash
omarchy-shell pomodoro <open|close|toggle|toggleRunning|pause|start|skip|restart|reset|health>
```

`open`, `close` e `toggle` mexem na janela. `toggleRunning` alterna entre
contar e parar, `pause` só pausa, `start` só começa se estiver parado, `skip`
pula a fase, `restart` devolve a fase ao tempo cheio, `reset` zera o ciclo.
`health` imprime fase, se está rodando e quanto falta, em JSON.

Para ligar um atalho, em `~/.config/hypr/bindings.conf`:

```
bind = SUPER, P, exec, omarchy-shell pomodoro toggleRunning
```

## Atualizar e remover

```bash
omarchy plugin update othavi0.pomodoro && omarchy restart shell
```

O `restart` é obrigatório. O plugin declara `keepLoaded: true` para que o
timer continue contando quando o widget é desmontado, e o efeito colateral é
que o serviço antigo sobrevive ao reload. Sem reiniciar a shell, o código
novo não entra.

```bash
omarchy plugin remove othavi0.pomodoro
```

## Como funciona

O plugin tem três peças. `Service.qml` é o único por shell: ele guarda o
timer, escreve o arquivo de estado, dispara notificação e som e registra o
alvo IPC. `BarWidget.qml` é um por monitor e desenha o anel, o MM:SS e o
popup. `Model.js` é a lógica pura, sem Qt, e decide toda transição.

A fase guarda o instante em que termina, em epoch de milissegundos, e não um
contador. "Quanto falta" é uma subtração. Daí vêm os comportamentos que
importam:

- Suspender ou desligar a máquina por mais de 120 segundos rebobina a fase
  para o tempo cheio, pausada, sem notificação. A fase não terminou, a
  máquina saiu.
- Reiniciar a shell retoma de onde estava. O estado vai a disco a cada 30
  segundos e em toda ação do usuário.
- Um foco pulado não conta para a pausa longa.
- Mudar uma duração só afeta uma fase pausada que ainda está no tempo cheio.
  Nos outros casos a mudança vale no próximo ciclo.
- A notificação e o som só saem no fim natural de uma fase. A notificação
  vem do `omarchy-notification-send` e o som de `pw-play`, `paplay`, `mpv` ou
  `ffplay`, o que existir. Clicar na notificação inicia a próxima fase.

As cores vêm do tema do Omarchy. O plugin não tem paleta própria.

## Desenvolvimento

```bash
node test/model.test.js   # 36 testes da lógica pura, sem Qt
scripts/verify.sh         # validate, qmllint, testes e render do anel
scripts/verify.sh --live  # o acima mais o smoke na shell rodando
scripts/dev.sh --restart  # copia o checkout para o diretório do plugin
```

`scripts/dev.sh` faz `rsync` para `~/.config/omarchy/plugins` porque o
validador recusa qualquer symlink dentro do diretório do plugin. Aceita
`--enable` e `--restart`.

Salvar `BarWidget.qml` ou `Panel.qml` recarrega o plugin em poucos
milissegundos. `Service.qml` não recarrega: por causa do `keepLoaded`, é
`omarchy restart shell` toda vez.

O `qmllint` e o `qmltestrunner` ficam em `/usr/lib/qt6/bin`. Não há nenhum
dos dois no PATH desta máquina.

## Smoke manual

Depois de instalar, confira na tela:

1. A barra mostra o anel e o tempo no formato MM:SS.
2. O clique esquerdo abre o popup na aba Pomodoro.
3. Arrastar um slider da aba Config não fecha o popup.
4. Com o timer rodando, `omarchy restart shell` retoma a contagem de onde
   estava, sem notificação espúria.

## Licença

MIT. Veja [LICENSE](LICENSE).
