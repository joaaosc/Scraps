# Conferência manual

A compilação e os testes de regras ficam no workflow. Esta lista cobre o uso
no computador e nos dispositivos reais.

## Mac

Instalar com `Scripts/dev-install.sh` e conferir:

- [ ] **Spotlight:** digitar Scraps e pressionar Tab. Nova nota aparece primeiro,
  seguida de nota só desta sessão, escolha de cor e ajustes. As notas escritas
  não aparecem nessa lista. Se o app não aparecer, conferir se está permitido
  em Ajustes do Sistema › Apple Intelligence e Siri › Apps.
- [ ] **Criação:** ⌘N abre uma nota. Atalhos/Siri com texto criam uma nota com
  esse texto, sem uma nota vazia adicional.
- [ ] **Sessão:** uma nota de sessão aceita texto e cor e desaparece ao sair
  do app. As notas comuns voltam depois de abrir novamente.
- [ ] **Edição:** negrito, itálico, listas e caixas de marcar continuam iguais
  após reabrir. Copiar e enviar uma nota ao Notas preserva o texto e a ênfase.
- [ ] **Recolhimento:** ⌘M e duplo clique no título alternam. Mover a barra
  recolhida e expandir preserva o tamanho anterior e a posição alcançada.
- [ ] **Foco:** com duas notas, os comandos agem na que tem o teclado.
  Ao abrir Ajustes, os comandos por nota ficam indisponíveis.
- [ ] **Recuperação:** fechar uma nota com texto a coloca em Apagadas
  recentemente. Recuperar devolve texto, formatação, cor e posição.
  Fechar todas segue o mesmo comportamento.
- [ ] **Mesas e tela cheia:** com Mostrar em todas as Mesas ativado, conferir
  a nota em outra Mesa, sobre um app em tela cheia e no Stage Manager.
- [ ] **Atalho global:** ativar em Ajustes e pressionar ⌃⌥⌘N com outro app
  em primeiro plano. Uma nota nova recebe o teclado.
- [ ] **Aparência:** conferir modo claro/escuro, Aumentar Contraste,
  Reduzir Transparência e VoiceOver. Botões e cores têm nomes compreensíveis.
- [ ] **Idioma:** com o sistema em português do Brasil, conferir menus,
  ajustes, cores, mensagens e as quatro ações do Spotlight.

## iPhone e iPad

- [ ] Grade, lista e busca funcionam em retrato/paisagem e em janelas estreitas
  do iPad, inclusive com texto aumentado.
- [ ] Criar, editar, fechar e recuperar uma nota mantém seu conteúdo.
- [ ] Sair para outro app e voltar preserva a última edição.
- [ ] Compartilhar uma nota com negrito/itálico mantém a ênfase no destino que
  aceita RTF; destinos de texto recebem as mesmas palavras.
- [ ] Notas de sessão desaparecem quando o app é encerrado.
- [ ] VoiceOver identifica ações, cores e estados de salvamento.

## Distribuição

Os arquivos Release de validação não substituem assinatura Apple Distribution.
Na equipe configurada, executar `Scripts/archive.sh macOS` e
`Scripts/archive.sh iOS`; validar pelo Organizer do Xcode antes do envio.
Conferir as URLs de suporte/privacidade e os textos em
[AppStore.md](AppStore.md).
