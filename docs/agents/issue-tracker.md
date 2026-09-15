# Issue tracker: GitHub

Issues e specs deste repo vivem nas GitHub Issues de
`larissa04alves/omadoro`. Toda operação usa a CLI `gh`, dentro do
clone, que infere o repo pelo `git remote`.

## Convenções

- **Criar issue**: `gh issue create --title "..." --body "..."`. Corpo de
  várias linhas vai por heredoc ou `--body-file`.
- **Ler issue**: `gh issue view <n> --comments`.
- **Listar**: `gh issue list --state open --json number,title,body,labels`.
- **Comentar**: `gh issue comment <n> --body "..."`.
- **Rótulos**: `gh issue edit <n> --add-label "..."` e `--remove-label "..."`.
- **Fechar**: `gh issue close <n> --comment "..."`.

## Pull requests como superfície de pedidos

**PRs como pedidos: não.** Mude para `sim` se PRs externos passarem a valer
como pedido de feature; o `/triage` lê esta flag.

## Quando uma skill diz "publicar no issue tracker"

Crie uma GitHub issue.

## Quando uma skill diz "buscar o ticket"

Rode `gh issue view <n> --comments`.

## Conta

O repo é da larissa. Ações que aparecem em nome do dono (submissão ao
marketplace, releases) saem com a conta dela ativa no `gh`:
`gh auth switch --user larissa04alves`.
