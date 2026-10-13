# Scraps

Notas adesivas nativas para macOS 27, iPhone e iPad: uma evolução do Stickies,
com texto legível, controles do sistema e aparência adaptada a cada dispositivo.

No Mac, cada nota é uma janela independente. É possível escolher entre vidro
e seis cores, recolher à primeira linha, manter na frente de outros apps e
mostrar em todas as Mesas. O atalho global opcional ⌃⌥⌘N cria uma nota sem
sair do trabalho atual.

O editor compartilhado oferece estilos de título, cabeçalho, legenda e código,
negrito, itálico, sublinhado, tachado, destaque, links, listas e caixas de marcar.
A biblioteca permite buscar, favoritar, etiquetar, arquivar e duplicar.
As notas são salvas automaticamente no dispositivo. Fechar uma nota a move
para Apagadas recentemente por 30 dias. Notas de sessão ficam só na memória.
Arquivos anteriores continuam sendo lidos, e arquivos danificados são
preservados.

O Spotlight recebe somente quatro ações: nova nota, nota de sessão, nova nota
com escolha de cor e ajustes. O texto das notas permanece fora do índice.
Siri e Atalhos também podem criar notas com texto e cor ou mostrar todas elas.

No iOS e iPadOS, a biblioteca adapta a grade ou lista ao espaço disponível,
com busca, edição e compartilhamento nativos. No Mac, a biblioteca abre com ⌘0.
O app usa inglês ou português do Brasil, aceita texto Unicode e datas locais.

A sincronização opcional usa a base privada do iCloud, combina alterações
independentes e preserva textos concorrentes como cópias recuperadas. Handoff
continua a edição entre Mac, iPhone e iPad. Widgets nativos mostram notas e
listas interativas ou abrem uma captura rápida; notas de sessão ficam fora deles.
Uma animação breve em Metal acompanha criação e troca de cor, respeitando as
preferências de acessibilidade e parando quando termina.

## Requisitos

- macOS 27 e Xcode 27, em Mac com Apple silicon;
- iOS 27 ou iPadOS 27 para o app móvel;
- Metal Toolchain instalado em Xcode › Settings › Components;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 para regenerar o projeto.

## Build

```sh
xcodebuild -downloadComponent metalToolchain
xcodegen generate
swift test --package-path Packages/StickyKit
xcodebuild -project Scraps.xcodeproj -scheme Scraps -destination 'platform=macOS,arch=arm64' -derivedDataPath build.noindex/DerivedData build
xcodebuild -project Scraps.xcodeproj -scheme ScrapsMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath build.noindex/DerivedData build CODE_SIGNING_ALLOWED=NO
```

Os testes de domínio, armazenamento, listas e dados móveis também rodam em
Linux com Swift 6.4. O workflow inclui builds nativos e os testes do pacote no
Xcode 27. Não há testes que controlem o teclado do Spotlight.

## Instalação e distribuição

```sh
Scripts/dev-install.sh
Scripts/archive.sh macOS
Scripts/archive.sh iOS
```

A instalação registra a cópia em `/Applications` usada pelo Spotlight. O
arquivamento exige certificados Apple Distribution e perfis da equipe.

Para atualizar uma cópia local depois de uma nova versão na `main`:

```sh
git fetch origin
git switch main
git pull --ff-only origin main
xcodegen generate
Scripts/dev-install.sh
```

O instalador aguarda o encerramento, verifica a nova cópia e preserva a anterior
na Lixeira. Um `git pull` sozinho atualiza o código, sem substituir o app instalado.

Para testar iPhone/iPad, abrir `Scraps.xcodeproj`, escolher o scheme
**ScrapsMobile** e executar com ⌘R num simulador com iOS 27. Em um aparelho real,
configurar a equipe e a assinatura automática nos alvos do app e dos widgets.
iCloud exige o contêiner e as capacidades descritos em
[CloudKit.md](Documentation/CloudKit.md). O roteiro inclui a
etapa de TestFlight e as conferências manuais de idiomas e acessibilidade.

Consulte [preparação para a loja](Documentation/AppStore.md),
[conferência manual](Documentation/Validation.md),
[privacidade](Documentation/Privacy.md) e [licença](LICENSE).
As correções de integridade e internacionalização estão registradas na
[auditoria da versão](Documentation/Audit.md).

## Estrutura

- `App/Scraps` e `App/ScrapsMobile`: ciclo de vida, menus e atalhos.
- `App/ScrapsWidgets`: extensões WidgetKit de Mac e iOS.
- `App/Shared`: ícone e cor de destaque.
- `StickyDomain`: notas, formatação portátil e ações fixas.
- `StickyStorage`: arquivos atômicos, sessões em memória e recuperação.
- `StickyEditor`: editor nativo e paleta compartilhados.
- `StickyUI`: janelas do Mac, salvamento e envio ao Notas.
- `StickyMobileUI`: biblioteca, navegação e edição no iPhone/iPad.
- `StickySync`: motor CloudKit e estado de sincronização.
- `StickyIntents`: entidades do Spotlight e ações de Siri/Atalhos.
- `project.yml`: fonte do projeto Xcode.

O registro por funcionalidade e as verificações pendentes estão em
[HANDOFF.md](HANDOFF.md). O desenvolvimento usa somente a branch `main`.
