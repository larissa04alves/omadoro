# Docs de domínio

Como as skills de engenharia consomem a documentação de domínio deste repo.

## Antes de explorar, leia

- `CONTEXT.md` na raiz: o glossário. Único contexto.
- `docs/adr/`: as decisões que tocam a área em que você vai mexer.

Se um arquivo não existir, siga em silêncio. O `/domain-modeling` cria os
dois quando um termo ou uma decisão de fato se resolve.

## Estrutura

```
/
├── CONTEXT.md
├── docs/
│   ├── adr/
│   │   ├── 0001-plugin-qml-puro-sem-binario.md
│   │   └── ...
│   ├── agents/
│   └── publicar-no-marketplace.md
└── *.qml, Model.js
```

## Use o vocabulário do glossário

Quando o texto nomear um conceito do domínio (título de issue, nome de teste,
hipótese), use o termo como o `CONTEXT.md` define. Não derive para os
sinônimos listados em `_Avoid_`. Conceito sem entrada no glossário é sinal:
ou é linguagem inventada, ou é lacuna para o `/domain-modeling`.

## Sinalize conflito com ADR

Se a saída contradiz um ADR, diga explicitamente em vez de passar por cima:

> _Contradiz o ADR-0003 (IPC único no Service), mas vale reabrir porque..._
