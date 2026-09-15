# Como publicar e atualizar o plugin no marketplace do Omarchy

Este guia cobre a primeira listagem em <https://plugins.omarchy.org> e as
atualizações depois dela. Fonte: `SUBMISSION.md`, `SECURITY.md` e
`VERIFICATION.md` do repositório `omacom/omarchy-plugin-marketplace`, lidos
em 2026-09-15.

## O que o marketplace exige do repositório

- Repositório público no GitHub, submetido pela URL raiz, sem `/tree/...`.
- Um só plugin, com `manifest.json` na raiz.
- README na raiz com instruções de instalação e remoção.
- Arquivo de licença na raiz e dependências externas documentadas.
- Id único fora do namespace `omarchy.*`. O id é permanente: um id listado,
  aposentado ou renomeado nunca volta a ficar disponível (ADR-0006).
- Opcional: uma imagem `preview.png` (ou jpg, jpeg, webp, avif) na raiz. O
  marketplace redimensiona sozinho. Limite de 50 MB e 40 megapixels.

Este repo atende a tudo isso desde o merge do PR #4.

## O que a validação automática checa

A submissão abre uma issue no repositório do marketplace. Um bot valida o
commit atual da branch padrão: estrutura do repositório, manifest e
compatibilidade com o Omarchy Quattro. Não é revisão de segurança.

Um segundo bot, a Automated Security Baseline, lê o mesmo commit sem executar
nada e procura um conjunto fixo de padrões: download direto para shell,
`cargo install --git` sem `--rev`, execução de git externo sem commit fixo,
sudoers `NOPASSWD` perigoso e controle de processo privilegiado a partir de
PID em `/tmp`. Também marca capacidades que pedem revisão humana:
instalador, gerenciador de pacotes, `sudo` ou `pkexec`, build remoto, binário
executável, `systemctl` ou `systemd-run`, sudoers. Este plugin não usa nenhum
deles. O resultado esperado é `passed`.

Um mantenedor então aplica `approved-and-verified`, e a listagem entra ligada
ao SHA exato validado.

## Submeter pela primeira vez

1. Confirme que `master` tem tudo o que deve ser listado. Um commit novo na
   branch depois da validação invalida a validação.
2. Ative a conta do dono do repo no `gh`:

   ```bash
   gh auth switch --user larissa04alves
   ```

3. Escreva o corpo da issue. As seis seções ficam nesta ordem, e o texto dos
   cinco itens do checklist não muda:

   ```markdown
   ### Repository URL

   https://github.com/larissa04alves/omadoro

   ### Category

   Productivity

   ### Tags

   bar, quickshell

   ### Suggest a missing tag

   _No response_

   ### Maintainer notes

   Runs entirely inside omarchy-shell (QML + JS, no binary, no build step).
   Writes only its own state file under $XDG_STATE_HOME/larissa04alves.omadoro/
   and its own inline entry in shell.json through the shell API. Sound uses
   whichever of pw-play, paplay, mpv or ffplay exists; notifications use
   omarchy-notification-send. scripts/ and test/ are development-only.

   ### Submission checklist

   - [x] The repository is public and contains installation and removal instructions.
   - [x] I have documented the plugin license and any external dependencies.
   - [x] I confirm that I own or have permission to submit this plugin and its preview assets.
   - [x] The plugin does not overwrite user configuration without explicit consent.
   - [x] I understand that approval is for listing and is not a security review.
   ```

   Categorias válidas: Appearance, Desktop, Developer Tools, Hardware, Kids,
   Productivity, System, Widgets, Other. Tags válidas, de uma a três: ai,
   bar, education, games, hyprland, kids, launcher, media, power-management,
   quickshell, security, system, workspaces.

4. Abra a issue. Pelo formulário em
   <https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml>
   ou pela CLI:

   ```bash
   gh issue create \
     --repo omacom/omarchy-plugin-marketplace \
     --title "[Plugin]: Omadoro" \
     --body-file /tmp/omarchy-plugin-submission.md
   ```

5. Acompanhe a issue. O bot mantém um comentário de validação e um da
   baseline de segurança e os atualiza a cada tentativa. Se algo falhar,
   corrija no repositório ou edite a issue. Não abra uma segunda submissão.

## Atualizar a listagem depois de um merge

A listagem aponta para um SHA exato. Quando `master` avança, o marketplace
mostra "Update unverified" até alguém pedir a promoção do commit novo.

1. Anote o SHA completo de `master`: `git rev-parse origin/master`.
2. Abra o formulário de verificação em
   <https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml>,
   escolha "Verify and publish a newer upstream commit" e informe id
   `larissa04alves.omadoro`, a URL raiz do repositório e o SHA.
3. Os mesmos dois bots rodam no commit novo. A listagem antiga fica de pé até
   um mantenedor aprovar.

Os comandos `omarchy plugin add` e `omarchy plugin update` clonam o HEAD da
branch, não o SHA listado. Quem instala recebe sempre o `master` atual.
