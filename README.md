# Forever Planner

> Leveling addon for **World of Warcraft: Forever** (interface 16001). Ranks quest hubs by XP/hour, builds a route through each hub and points the way with a GPS arrow. Requires QuestieDB (Forever build). UI in Portuguese (pt-BR).

Addon de leveling para **World of Warcraft: Forever** (Classic+, interface 16001).
Pensado para Warlock Undead, mas funciona pra qualquer classe e raça.

- **Guia**: ranking dos *hubs* da zona por XP/hora. Cada hub vira um circuito: pegar todas as quests, fazer os objetivos na ordem de menor deslocamento e entregar tudo. Conta o XP dos mobs, o tempo parado e o rested. Quest fraca sai do circuito, a não ser que libere uma cadeia: a cadeia é avaliada como um bloco, pelo XP de todos os passos. Elite e dungeon ficam à parte.
- **Level**: hubs para o seu nível perto de você (zona atual e vizinhas), o que resolver antes de sair (inclusive quest pronta com entrega em outra zona, com o caminho) e se vale a viagem para outro mapa, com o tempo real do caminho (a pé, voo, zepelim ou barco, pedra de lar). Hub alto demais aparece como "volte no nível N". Você escolhe e segue.
- **Quests**: ranking das quests da zona, uma a uma, por *valor ÷ tempo*. O valor é XP da quest, XP dos mobs e upgrade de equipamento (com teto de 25%). A seção Level fica dentro desta aba.
- **Trilha**: zonas por faixa de 10 níveis, com alternativas e a viagem entre elas (voo, a pé pelas passagens entre zonas, pedra de lar).
- **Gear**: o melhor upgrade por slot até 3 níveis à frente, de quest, cadeia, masmorra, vendedor ou casa de leilões.
- **GPS**: aponta onde ir (pegar → objetivo → entregar). Usa uma seta na tela com distância, o pino nativo do mapa e o TomTom, se estiver instalado. A pé, a seta segue a estrada e, sem estrada, um caminho pelo relevo, passando pelas passagens entre zonas em vez de mandar subir a montanha. Quando o alvo está dentro de uma caverna, a seta leva até a entrada. Quando o objetivo é um objeto, a seta diz o que pegar ("pegue: Crate with Holes").
- **Macros**: leveling e avançadas para Warlock, Warrior, Mage e Druid, feitas para repeat (ex.: Razer Naga): alvo automático só em combate, listas de prioridade e `/castsequence`, criadas com 1 clique. Canalizados e controle vêm marcados "sem repeat". Dica para o spam: `/console Sound_EnableErrorSpeech 0` corta a voz de "não está pronto". O texto usa os nomes do seu client e só os feitiços que você conhece; quando você aprende um feitiço, as macros já criadas se atualizam sozinhas.
- **Procurar grupo**: na aba Buscar do LFG, um painel ao lado lista os grupos do seu nível primeiro. "Chamar" abre o whisper do líder com o texto pronto (classe, nível, papel e atividade): é só apertar Enter. O painel marca quem você já chamou.
- **Builds**: talentos por faixa de nível, pesos de atributo editáveis, Legacy e dicas de rota.
- **Ferramentas**: todo comando `/fp` tem um botão aqui, agrupado por assunto, com o resultado na própria aba em vez do chat. Quem não decorou o comando acha a função por ela.

## Instalação

Antes de tudo, instale o **QuestieDB** (versão Forever) pelo CurseForge. Ele é obrigatório, porque traz a base de quests e NPCs. O TomTom (versão Forever) é opcional.

### Pelo instalador (Windows)

Abra o **PowerShell** (menu Iniciar → digite `PowerShell`) e cole:

```powershell
irm https://raw.githubusercontent.com/calucipher/forever_planner/main/install.ps1 | iex
```

O instalador acha a pasta do Forever, confere a versão instalada com a mais nova de [Releases](https://github.com/calucipher/forever_planner/releases/latest) e só baixa e instala se houver versão nova. **Para atualizar, rode o mesmo comando.** Ele troca a pasta `ForeverPlanner` inteira, então arquivo que saiu do addon também sai. Outros addons e as suas configurações (pasta `WTF/`) não são tocados.

Se o WoW estiver numa pasta diferente, ou se preferir ler o script antes de rodar, baixe o [`install.ps1`](https://github.com/calucipher/forever_planner/blob/main/install.ps1) e rode:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -WowPath "E:\World of Warcraft"
```

Outras opções: `-Zip <arquivo>` instala um zip já baixado, sem internet, e `-Force` reinstala a mesma versão.

### À mão

1. Baixe o `ForeverPlanner-<versão>.zip` da última versão em [Releases](https://github.com/calucipher/forever_planner/releases/latest).
2. Extraia o zip na pasta `Interface/AddOns/` do Forever (por exemplo, `C:\World of Warcraft\_forever_\Interface\AddOns\`). O resultado deve ser `Interface/AddOns/ForeverPlanner/ForeverPlanner.toc`.
3. Abra o jogo e digite `/fp`.

> O botão **Code → Download ZIP** desta página cria a pasta `forever_planner-main`, sem a subpasta. O jogo só carrega o addon se a pasta se chamar `ForeverPlanner`. Use o zip de Releases.

Para atualizar à mão, apague a pasta `ForeverPlanner` antiga e extraia o zip novo. As suas configurações ficam em `WTF/` e não se perdem.

## Uso

| Comando | O que faz |
|---|---|
| `/fp` | Abre ou fecha o painel (ou clique no botão do minimapa). Os comandos abaixo também têm botão na aba Ferramentas |
| `/fp minimapa` | Esconde ou mostra o botão do minimapa |
| `/fp entregar` | GPS segue o hub mais perto com quests prontas para entregar; sem nenhuma na zona, segue a entrega pronta mais perto de qualquer zona |
| `/fp limpar` | Lista as quests do log que não valem a pena e abandona só se você confirmar |
| `/fp bolsa` | Segue a melhor quest que dá bolsa (zona atual primeiro, depois menor nível) |
| `/fp bolsas` | Lista as quests de bolsa do personagem: zona, nível e situação |
| `/fp classe` | Lista as quests de classe (pets, bolsa de alma, Soran'ruk, Felsteed) e segue a melhor |
| `/fp marcos` | Próximos marcos da classe e perícias de arma que faltam treinar, com o Weapon Master |
| `/fp voos` | Mostra ou esconde os pontos de voo no mapa-múndi |
| `/fp lfg` | Abre o painel de procurar grupo. `/fp lfg texto <t>` e `/fp lfg solo <t>` trocam o texto do whisper; `/fp lfg padrao` volta ao original; `/fp lfg copiar` faz o Chamar só copiar o texto |
| `/fp diario on\|off\|limpar` | Liga, desliga ou apaga o diário (veja Limitações) |
| `/fp debug` | Liga/desliga o modo debug: registra as decisões do guia (gravado no disco no `/reload` ou logout). `/fp debug chat` mostra no chat também |
| `/fp diag` | Retrato do estado do guia no chat e no registro |
| `/fp auto` | Liga ou desliga o auto accept e o auto turn-in (padrão: ligado) |
| `/fp guia` | GPS segue o circuito do melhor hub da zona |
| `/fp zonas` | As 5 melhores zonas para o seu nível (XP/h, quests, viagem) e o melhor lugar para grind |
| `/fp next` | GPS segue a melhor quest da zona |
| `/fp clear` | Para o GPS |
| `/fp preset affliction\|demonology\|destruction` | Troca o perfil de pesos |
| `/fp ttk 12` | Ajusta o tempo médio por kill (em segundos) usado na estimativa |
| `/fp agressividade 50` | Tira do circuito a quest que rende menos de 50% da média do hub (0 = não tira nada) |
| `/fp macros` | Lista os feitiços das macros: ID, nome no seu client e se você conhece |
| `/fp calib` | Mostra o tempo por morte e o fator de XP medidos nas suas últimas mortes |
| `/fp stats <link>` | Mostra os stats que o client devolve para um item (serve de debug do score) |

- **Auto accept/turn-in**: aceita só as quests do plano (circuitos dos hubs da zona, a quest seguida e a continuação da que você acabou de entregar) e entrega sozinho. Quest fora do plano fica para você aceitar, com um aviso no chat. Na escolha de recompensa, pega o maior upgrade; sem upgrade, a que vende mais caro. Quest que cobra ouro não é entregue sozinha.
- **Automações**: cada automação tem uma chave na aba Ferramentas (aceitar, entregar, escolher recompensa, seguir a próxima, pontos de voo na rota, entrega no caminho, marcar o voo, voar sozinho).
- **Quest de elite ou masmorra**: ao aceitar, o addon pergunta "Pular" ou "Fazer em grupo". Elite em grupo volta à rota; a de masmorra aparece em `/fp masmorras`, junto da entrada.
- **Treinar**: botão "Treinar" na aba Guia (`/fp treinar`) leva ao treinador da classe mais perto e lista o que falta, com as habilidades novas do Forever marcadas. Na janela do treinador, o chat mostra o custo total e "Treinar tudo" compra o que o dinheiro der. `/fp ranks` acha botões da barra com rank velho e `/fp ranks trocar` troca.
- **Botão "+" ao lado da seta**: Melhor hub, Ir entregar e Limpar o log. A limpeza nunca toca em quest de classe, em cadeia que leva a upgrade ou a muito XP, nem em quest que não existia no Classic.
- O guia fica no hub que você escolheu até ele acabar; aí segue primeiro o hub com entregas prontas. Entregas prontas são feitas assim que você chega no NPC.
- **Botão do minimapa**: clique abre/fecha o painel, clique direito segue o melhor hub, arraste para mover. O addon também aparece no menu de addons do minimapa.
- Na aba **Guia**, clique num hub para ver o circuito e em *Seguir este hub*. O GPS aponta a próxima parada e avança sozinho quando você pega, cumpre ou entrega.
- **Sugestão de zona**: no topo da aba Guia, quanto a zona atual rende e se vale ficar, ir para outra zona ou fazer grind (e onde). O chat avisa uma vez quando a zona acabou. É estimativa: conta a viagem e as cadeias, e fica melhor depois da calibração.
- **Pontos de voo no mapa**: verde é ponto descoberto, vermelho é ponto que falta abrir, amarelo é a conferir. O jogo não diz fora do mestre de voo quais você conhece: abra a janela de um mestre de voo uma vez em cada continente para o addon aprender. Clique no pino para a seta ir até ele.
- Quando o caminho passa perto de um ponto de voo vermelho (até 400 jardas de desvio, contando a ida até o hub), entra a parada **Abrir ponto de voo**. A seta também usa os pontos que você conhece para voar quando compensa. Ao abrir o mestre de voo, o destino da seta já vem marcado na janela.
- O circuito evita ir e voltar pelo mesmo caminho, e uma quest pronta de outro hub com o NPC no caminho entra como **entrega no caminho**.
- Com a pedra de lar em recarga por poucos minutos, a viagem considera esperar e usar quando isso é mais rápido que andar.
- **Quest cinza** (6 níveis ou mais abaixo de você) sai da rota, a não ser que seja de classe, de bolsa, entrega pronta ou leve a um item bom (upgrade significativo ou item azul que você usa, na própria quest ou mais adiante na cadeia). Nesse caso o nome mostra "(leva a: item)". Quest do log que rende pouco também sai da rota, mas fica no log: abandone pelo `/fp limpar` se quiser.
- Quest cujos mobs do objetivo estão, em média, mais de 1,5 nível acima de você fica fora do circuito como **mobs altos, volta no N**. Ela entra sozinha quando você chega no nível N.
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
| Estradas da seta | Geradas do terreno do client do Forever (texturas de estrada) |
| Stats dos itens | API do jogo (`C_Item.GetItemStats`), complementada pelo tooltip para dano de escola |

Nada é raspado do Wowhead. Os termos do Wowhead proíbem coleta automatizada, mesmo para uso pessoal.

## Limitações conhecidas

- Os **pesos de atributo são heurísticos**. Não existem pesos oficiais do Forever. Ajuste na aba Builds e calibre o TTK.
- Os **nomes de API** são da família Mainline 12.1.5. Confira no client live se algum falhar.
- Os **padrões de tooltip em pt-BR** são melhor esforço. Use `/fp stats` para conferir.
- Nas **macros**, os IDs de feitiço são os do Classic. Se algum não resolver no Forever, a macro usa o nome em inglês (confira com `/fp macros`). A FP Rotacao não usa a varinha: faz Agony, Corruption, Immolate, Siphon Life e 2 Shadow Bolts e recomeça. Para a varinha, use a FP Varinha.
- O planejador não replica as blacklists internas do Questie. Ele exclui eventos sazonais, PvP, quests de profissão e de outras classes, e quests 5+ níveis acima do seu.
- O **ouro** só entra na conta depois que você vê a recompensa (`goldToXP` padrão = 0).
- A **taxa de drop** é fixa em 45% (a QuestieDB não traz a taxa). O **XP de mob** usa a fórmula do Classic até a calibração medir o do Forever.
- O **progresso dos objetivos** é lido do log e casado pelo nome do mob ou item. Em client pt-BR, se o nome não casar, o GPS aponta para todos os objetivos.
- O guia trabalha na zona atual; a aba **Level** é que compara zonas vizinhas e viagens. Os tempos de voo, zepelim e pedra de lar são estimativas.
- Em combate e em luta de chefe o painel de grupo mostra "lista indisponível agora" (o jogo esconde a lista dos addons nessa hora). O addon nunca manda mensagem nem convida sozinho: quem aperta Enter é você.
- O **diário** grava na sua máquina o que você faz no jogo (quests, mortes, viagens) em `ForeverPlannerJournal`, para calibrar as estimativas. Ocupa até ~8 MB. Não sai do seu computador. Desligue com `/fp diario off`.

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
