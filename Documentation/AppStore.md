# Preparação para a App Store

Nome de listagem proposto: **Scraps — Sticky Notes**. O nome exibido no
dispositivo continua sendo **Scraps**. A disponibilidade do nome depende do
cadastro no App Store Connect.

Categoria: produtividade. Plataformas: macOS 27, iOS 27 e iPadOS 27. O código
está sob licença proprietária, com todos os direitos reservados. A distribuição
pela loja usa a licença padrão da Apple.

## Texto em português

**Subtítulo:** Ideias sempre por perto

Anote uma ideia, uma lista ou um lembrete sem interromper o que está fazendo.
No Mac, cada nota tem sua própria janela: escolha uma cor, mantenha na frente,
recolha à primeira linha e deixe visível em todas as Mesas.

Escreva com estilos, negrito, itálico, destaque, links, listas e caixas de marcar.
Organize com favoritos, etiquetas e arquivo. Crie notas que duram
apenas uma sessão, recupere notas fechadas por 30 dias e compartilhe o que
merece ficar no Notas da Apple.

No iPhone e no iPad, encontre suas notas numa biblioteca adaptável. As notas
ficam no dispositivo ou, se você ativar, sincronizam pela sua conta iCloud.
Widgets mantêm ideias e tarefas à vista. Handoff continua a edição entre seus
dispositivos, sem publicidade ou rastreamento.

Palavras-chave: notas,adesivas,lembretes,rascunho,listas,tarefas,stickies

## English

**Subtitle:** Keep your thoughts close

Capture a thought, a list, or a little reminder without losing your place.
On Mac, every sticky has its own window. Choose a color, float it above other
apps, collapse it to its first line, or keep it visible across desktops.

Use text styles, bold, italic, highlights, links, lists and checklists.
Organize with favorites, tags and an archive. Make a session-only note, recover
closed notes for 30 days, and share anything worth keeping with Apple Notes.

On iPhone and iPad, browse an adaptable note library. Your notes stay on your
device, or optionally sync through your private iCloud account. Native widgets
keep ideas and tasks in sight, and Handoff continues editing on your devices.
There is no advertising or tracking.

Keywords: sticky,notes,reminders,scratchpad,lists,tasks,stickies

## Validação antes de enviar

1. Rodar os testes do pacote e os builds limpos com Xcode 27.
2. Conferir manualmente aparência clara/escura, Aumentar Contraste, Reduzir
   Transparência, VoiceOver, foco, atalho global, Mesas e tela cheia.
3. Instalar a cópia do Mac e conferir manualmente Spotlight: Scraps → Tab.
   A primeira ação deve ser Nova nota; a ordem final depende do Spotlight.
4. Arquivar com certificado Apple Distribution: `Scripts/archive.sh macOS`
   e `Scripts/archive.sh iOS`. A equipe precisa de certificado e perfil de
   distribuição válidos para os apps e extensões, incluindo as capacidades
   descritas em [CloudKit.md](CloudKit.md). Publicar o esquema CloudKit em
   Production antes de TestFlight.
5. Validar o arquivo no Organizer do Xcode; conferir assinatura e entitlements.
   O produto macOS deve ter sandbox e não pode incluir get-task-allow.
6. Cadastrar URLs públicas de suporte e privacidade, confirmar o nome e preparar
   screenshots reais das duas plataformas. Este repositório não publica URLs.
7. No formulário de privacidade, aplicar as definições atuais da Apple ao
   conteúdo privado do CloudKit. O desenvolvedor não recebe telemetria nem
   acessa o conteúdo, mas a sincronização deve constar da política pública.

## Disponibilidade internacional

O app inclui interface e atalhos em inglês e português do Brasil. Cadastrar
os textos acima como inglês dos EUA e português do Brasil no App Store Connect;
outros territórios recebem o idioma de fallback disponível. Os limites são
30 caracteres para nome/subtítulo e 100 para palavras-chave.

Usar o mesmo registro do app para Mac, iPhone e iPad, com o bundle identifier
`com.joaocosta.Scraps`, se a distribuição incluir compra universal. Isso não
ativa sincronização por si só: o contêiner CloudKit também precisa estar configurado. O requisito macOS/iOS/iPadOS 27 deve
aparecer na listagem; o app Mac é destinado a Apple silicon.

Antes de habilitar territórios, definir no App Store Connect os países de
distribuição, preço, classificação etária e informações fiscais/comerciais da
conta. Para distribuição na União Europeia, declarar o status de comerciante
e preencher os dados solicitados pela Apple. As URLs de suporte e privacidade
devem estar acessíveis publicamente aos usuários dos territórios selecionados.

Os artefatos de desenvolvimento têm assinatura ad hoc. Eles não substituem um
arquivo assinado para distribuição. Nenhum envio ou publicação é automatizado.
