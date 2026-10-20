# AI Agents: estudo descartável de layout

Pergunta: **como priorizar sessões e pendências na ilha, preservando o acesso aos oito grupos de informação existentes?**

Preferência confirmada em 2026-10-20: ao abrir AI Agents, o usuário quer primeiro
ver sessões e responder pendências. O usuário preferiu A e pediu o refinamento
abaixo no Firefox. A implementação nativa ainda não faz parte deste estudo.

Refinamento confirmado: retirar a expansão de consumo/histórico do fim da lista;
mostrar o tempo até a renovação da sessão junto ao percentual livre de cada
provedor; usar um botão de ícone de medidor no rodapé para abrir limites e uso,
com tooltip e nome acessível. Refinamento seguinte: percentual e renovação na
mesma linha, apenas ↻ e o tempo, sem texto adicional; ícone de limites e uso
sem fundo ou borda. Uso/histórico continuam acessíveis nesse detalhe.
O rodapé foi compactado: espaçamento superior de 4 px, intervalos menores entre
leituras e alvo do ícone de 24 px, mantendo a tipografia.
Altura confirmada: a lista principal de A se ajusta ao conteúdo até 320 px,
com rolagem apenas nas sessões ao atingir esse limite e rodapé sempre visível.
Detalhes e consulta de uso mantêm o orçamento de 320 px para leitura.
Experimento seguinte: em A, o botão da sessão expande sua conversa no próprio
card, com toda a largura disponível, em vez de navegar para outra tela. Apenas
uma sessão se expande por vez; o botão superior recolhe. A ilha cresce até o
limite e a lista rola, preservando as demais sessões e o rodapé. O campo de
resposta e as permissões continuam dentro do conteúdo expandido. B/C mantêm suas
estruturas para comparação. Esta interação ainda precisa do retorno do usuário.

## Rodar

Na raiz deste worktree:

```sh
python3 Sources/Vorssaint/UI/Notch/AI-Agents-Layout.prototype/serve.py
```

Abra <http://127.0.0.1:8765/?variant=A>. Sem dependências. `--port` troca a porta.
Também funciona abrindo `index.html` diretamente. Estado só em memória; apenas
o parâmetro de variante permanece no endereço. Nenhuma conexão com app, terminal,
histórico ou conta. Nenhuma aprovação, mensagem ou renovação real.

## Propostas

| Variante | Estrutura | Hipótese |
| --- | --- | --- |
| A — Fila de atenção | Pendências no topo, sessões em linhas, percentual e renovação na base; ícone abre uso | Preferida pelo usuário; elimina o acesso redundante no fim da lista |
| B — Sessões / Uso | Duas áreas, tabela compacta de sessões e uma área de consulta | Separar acompanhamento de análise libera espaço |
| C — Lista + conversa | Lista lateral, detalhe selecionado e limites na base | Várias conversas ficam navegáveis sem voltar de uma tela |

Use as setas flutuantes ou ←/→, preservando os dados do cenário ao comparar.
As teclas não são interceptadas em campos editáveis ou seletores. A barra só
aparece em arquivos locais/loopback. O protótipo não é referenciado pelo build
nativo e fica apenas na branch `prototype/ai-agents-layout`.

Compare: uma aprovação, dois agentes trabalhando, seis conversas no mesmo
projeto, um limite crítico e nenhuma sessão aberta. Reinicie para desfazer as
ações simuladas. Expanda “Estado da simulação” para inspecionar o estado completo.
Todas as oito famílias continuam acessíveis em cada variante, por agrupamentos
distintos. Contas extras Codex ficam no detalhe de limites.

## Inventário e prioridade

Fonte: `../NotchAgentsView.swift` e
`../../../Services/Notch/NotchAgentSupport.swift` (a partir de `f00d2ab3`).
A enumeração contém `limits, spend, live, trend, models, projects, activity, resets`.
É também a ordem padrão; ordem e visibilidade já são personalizáveis.

1. **Pendências**: uma faceta de Live, não uma nona fonte de dados. Subir perguntas
   e permissões Claude que bloqueiam uma conversa. Não inventar aprovação Codex.
2. **Sessões**: identidade de conversa, projeto, estado, atividade e interação.
   Duas sessões do mesmo projeto continuam distintas pelo assunto/provedor.
3. **Limites**: leitura resumida, detalhe de janelas e contas. Resets ficam com
   a conta Codex padrão a que pertencem. Limites críticos recebem destaque.
4. **Gasto**: chamar de valor equivalente de API, com tokens/cache e período.
   Um alerta de orçamento pode elevar essa informação; não é implementado aqui.
5. **Tendência, Modelos, Projetos, Atividade**: consulta progressiva em Uso.
   Preservar o resumo de uso ao vivo de OpenCode/Copilot sem sugerir interação.

## Contexto visual e limites

O hospedeiro é SwiftUI, sem rota web existente. A página representa a ilha junto
da câmera, faixa superior, acessos rápidos e contexto de desktop; não substitui
a janela real. Larguras 480/560 e orçamento de conteúdo de 320 px seguem
`NotchLayout`/`NotchGeometry`. Em telas pequenas a prévia se ajusta sem prometer
escala física exata. Tipografia de sistema, conteúdo alinhado à esquerda,
preto da ilha (#000), painel neutro (#24262b), texto (#f2f3f6), Claude (#e1a083),
Codex (#9caefb), atenção (#efc37c). A cor indica provedor/estado.

Esboços estruturais:

```text
A                   B                    C
pendência           Sessões | Uso        lista | conversa
sessão em linha     tabela de sessões    lista | ações
ícone abre uso      OU análise completa  lista | resposta
limites fixos       alerta contextual    limites fixos
```

A diferença está na navegação e na distribuição de espaço, não na paleta.
A camada externa contém inventário, justificativas e estado: não faz parte da
interface proposta para o produto. Os cenários têm dados fictícios e não provam
integração nativa, foco AppKit, permissões ou encaminhamento a terminais.

Verificação desta entrega: JavaScript passou na checagem de sintaxe, servidor
local entregou os arquivos, e o Firefox carregou A com os controles e conteúdos
esperados na árvore de acessibilidade. A captura visual travou e as tentativas
seguintes de inspecionar Firefox expiraram; Computer Use não recebeu autorização
para Chrome. A revisão visual completa de B/C e das duas larguras permanece
pendente. Não foram criados testes para este código descartável.

## Captura e próxima decisão

Branch de captura: `prototype/ai-agents-layout`. Este README é o ponteiro local
do estudo; não existe issue de implementação vinculada. Direção escolhida: A,
com acesso único a limites e uso por ícone e renovação visível no rodapé.
Revisar o refinamento no protótipo antes de reimplementar em SwiftUI.
Não promover este HTML para produção.
