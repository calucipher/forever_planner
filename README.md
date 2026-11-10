# Forever Planner

> Leveling addon for **World of Warcraft: Forever** (interface 16001). Ranks quest hubs by XP/hour, builds a route through each hub and points the way with a GPS arrow. Requires QuestieDB (Forever build). UI in Portuguese (pt-BR).

Addon de leveling para **World of Warcraft: Forever** (Classic+, interface 16001).
Pensado para Warlock Undead, mas funciona pra qualquer classe e raça.

- **Guia**: ranking dos *hubs* da zona por XP/hora. Cada hub vira um circuito: pegar todas as quests, fazer os objetivos na ordem de menor deslocamento e entregar tudo. Conta o XP dos mobs, o tempo parado e o rested. Quest fraca sai do circuito, a não ser que libere uma cadeia. Elite e dungeon ficam à parte.
- **Quests**: ranking das quests da zona, uma a uma, por *valor ÷ tempo*. O valor é XP da quest, XP dos mobs e upgrade de equipamento (com teto de 25%).
- **GPS**: aponta onde ir (pegar → objetivo → entregar). Usa uma seta na tela com distância, o pino nativo do mapa e o TomTom, se estiver instalado.
- **Macros**: leveling e avançadas para Warlock, Warrior, Mage e Druid, feitas para repeat (ex.: Razer Naga): alvo automático só em combate, listas de prioridade e `/castsequence`, criadas com 1 clique. Canalizados e controle vêm marcados "sem repeat". Dica para o spam: `/console Sound_EnableErrorSpeech 0` corta a voz de "não está pronto". O texto usa os nomes do seu client e só os feitiços que você conhece; quando você aprende um feitiço, as macros já criadas se atualizam sozinhas.
- **Builds**: talentos por faixa de nível, pesos de atributo editáveis, Legacy e dicas de rota.

## Instalação

1. Instale o **QuestieDB** (versão Forever) pelo CurseForge. Ele é obrigatório, porque traz a base de quests e NPCs.
2. Baixe o `ForeverPlanner-<versão>.zip` da última versão em [Releases](https://github.com/calucipher/forever_planner/releases/latest).
3. Extraia o zip na pasta `Interface/AddOns/` do Forever (por exemplo, `C:\World of Warcraft\_forever_\Interface\AddOns\`). O resultado deve ser `Interface/AddOns/ForeverPlanner/ForeverPlanner.toc`.
4. *(Opcional)* Instale o TomTom (versão Forever).
5. Abra o jogo e digite `/fp`.

> O botão **Code → Download ZIP** desta página cria a pasta `forever_planner-main`, sem a subpasta. O jogo só carrega o addon se a pasta se chamar `ForeverPlanner`. Use o zip de Releases.

Para atualizar, apague a pasta `ForeverPlanner` antiga e extraia o zip novo. As suas configurações ficam em `WTF/` e não se perdem.

## Uso

| Comando | O que faz |
|---|---|
| `/fp` | Abre ou fecha o painel (ou clique no botão do minimapa) |
| `/fp minimapa` | Esconde ou mostra o botão do minimapa |
| `/fp entregar` | GPS segue o hub mais perto com quests prontas para entregar |
| `/fp limpar` | Lista as quests do log que não valem a pena e abandona só se você confirmar |
| `/fp bolsa` | Segue a melhor quest que dá bolsa (zona atual primeiro, depois menor nível) |
| `/fp bolsas` | Lista as quests de bolsa do personagem: zona, nível e situação |
| `/fp classe` | Lista as quests de classe (pets, bolsa de alma, Soran'ruk, Felsteed) e segue a melhor |
| `/fp marcos` | Próximos marcos da classe e perícias de arma que faltam treinar, com o Weapon Master |
| `/fp debug` | Liga/desliga o modo debug: registra as decisões do guia (gravado no disco no `/reload` ou logout). `/fp debug chat` mostra no chat também |
| `/fp diag` | Retrato do estado do guia no chat e no registro |
| `/fp auto` | Liga ou desliga o auto accept e o auto turn-in (padrão: ligado) |
| `/fp guia` | GPS segue o circuito do melhor hub da zona |
| `/fp next` | GPS segue a melhor quest da zona |
| `/fp clear` | Para o GPS |
| `/fp preset affliction\|demonology\|destruction` | Troca o perfil de pesos |
| `/fp ttk 12` | Ajusta o tempo médio por kill (em segundos) usado na estimativa |
| `/fp agressividade 50` | Tira do circuito a quest que rende menos de 50% da média do hub (0 = não tira nada) |
| `/fp macros` | Lista os feitiços das macros: ID, nome no seu client e se você conhece |
| `/fp calib` | Mostra o tempo por morte e o fator de XP medidos nas suas últimas mortes |
| `/fp stats <link>` | Mostra os stats que o client devolve para um item (serve de debug do score) |

- **Auto accept/turn-in**: aceita as quests relevantes (pula evento sazonal, PvP, outra classe e vermelha demais) e entrega sozinho. Na escolha de recompensa, pega o maior upgrade; sem upgrade, a que vende mais caro. Quest que cobra ouro não é entregue sozinha.
- **Botão "+" ao lado da seta**: Melhor hub, Ir entregar e Limpar o log. A limpeza nunca toca em quest de classe, em cadeia que leva a upgrade ou a muito XP, nem em quest que não existia no Classic.
- O guia fica no hub que você escolheu até ele acabar; aí segue primeiro o hub com entregas prontas. Entregas prontas são feitas assim que você chega no NPC.
- **Botão do minimapa**: clique abre/fecha o painel, clique direito segue o melhor hub, arraste para mover. O addon também aparece no menu de addons do minimapa.
- Na aba **Guia**, clique num hub para ver o circuito e em *Seguir este hub*. O GPS aponta a próxima parada e avança sozinho quando você pega, cumpre ou entrega.
- Depois de 5 mortes, o tempo por morte e o fator de XP passam a ser os medidos no jogo (`/fp calib`).
- Clique numa quest para o GPS segui-la.
- Clique direito na seta para parar o GPS.
- Quando você entrega a quest seguida, o GPS escolhe sozinho a próxima melhor (`autoNext`).

## De onde vêm os dados

| Dado | Fonte |
|---|---|
| Quests, NPCs, spawns, cadeias, quem dá e quem entrega | QuestieDB (GPL-3.0) |
| Quais itens cada quest dá | QuestieDB (`Item.questRewards`, invertido no login) |
| XP | Valor real quando você abre a quest (fica no cache). Senão, tabela da QuestieDB. Senão, mediana por nível de quest (marcada com `*`) |
| Stats dos itens | API do jogo (`C_Item.GetItemStats`), complementada pelo tooltip para dano de escola |

Nada é raspado do Wowhead. Os termos do Wowhead proíbem coleta automatizada, mesmo para uso pessoal.

## Limitações conhecidas

- Os **pesos de atributo são heurísticos**. Não existem pesos oficiais do Forever. Ajuste na aba Builds e calibre o TTK.
- Os **nomes de API** são da família Mainline 12.1.5. Confira no client live se algum falhar.
- Os **padrões de tooltip em pt-BR** são melhor esforço. Use `/fp stats` para conferir.
- Nas **macros**, os IDs de feitiço são os do Classic. Se algum não resolver no Forever, a macro usa o nome em inglês (confira com `/fp macros`). Na FP Rotacao, o `null` que segura a sequência e a varinha logo depois do Shadow Bolt ainda precisam de teste no jogo.
- O planejador não replica as blacklists internas do Questie. Ele exclui eventos sazonais, PvP, quests de profissão e de outras classes, e quests 5+ níveis acima do seu.
- O **ouro** só entra na conta depois que você vê a recompensa (`goldToXP` padrão = 0).
- A **taxa de drop** é fixa em 45% (a QuestieDB não traz a taxa). O **XP de mob** usa a fórmula do Classic até a calibração medir o do Forever.
- O **progresso dos objetivos** é lido do log e casado pelo nome do mob ou item. Em client pt-BR, se o nome não casar, o GPS aponta para todos os objetivos.
- Rota entre zonas não entra: o guia trabalha na zona atual.

## Bugs e sugestões

Abra uma [issue](https://github.com/calucipher/forever_planner/issues) com:
- o que você fez e o que esperava;
- a versão do addon (`## Version:` em `ForeverPlanner.toc`);
- a saída de `/fp diag` (o comando copia o estado do guia para o chat e para o registro).

Pull requests não são aceitos por enquanto: o código é desenvolvido em outro lugar e cada versão substitui o conteúdo deste repositório.

## Aviso

Projeto de fã, sem vínculo com a Blizzard Entertainment. World of Warcraft é marca da Blizzard.

## Licença

Copyright (C) 2026 Calcifer Fallingstar

GPL-3.0 (ver `LICENSE.md`). Usa dados da [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0).
