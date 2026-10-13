# Scraps

Notas adesivas nativas para macOS 27, iPhone e iPad: uma evolução do Stickies,
com texto legível, controles do sistema e aparência adaptada a cada dispositivo.

No Mac, cada nota é uma janela independente. É possível escolher entre vidro
e seis cores, recolher à primeira linha, manter na frente de outros apps e
mostrar em todas as Mesas. O atalho global opcional ⌃⌥⌘N cria uma nota sem
sair do trabalho atual.

O editor compartilhado oferece negrito, itálico, listas e caixas de marcar.
As notas são salvas automaticamente no dispositivo. Fechar uma nota a move
para Apagadas recentemente por 30 dias. Notas de sessão ficam só na memória.
Arquivos anteriores continuam sendo lidos, e arquivos danificados são
preservados.

O Spotlight recebe somente quatro ações: nova nota, nota de sessão, nova nota
com escolha de cor e ajustes. O texto das notas permanece fora do índice.
Siri e Atalhos também podem criar notas com texto e cor ou mostrar todas elas.

No iOS e iPadOS, a biblioteca adapta a grade ou lista ao espaço disponível,
com busca, edição e compartilhamento nativos. Não há sincronização entre
dispositivos nesta versão. O app usa inglês ou português do Brasil.

## Requisitos

- macOS 27 e Xcode 27, em Mac com Apple silicon;
- iOS 27 ou iPadOS 27 para o app móvel;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 para regenerar o projeto.

## Build

```sh
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

Consulte [preparação para a loja](Documentation/AppStore.md),
[privacidade](Documentation/Privacy.md) e [licença](LICENSE).

## Estrutura

- `App/Scraps` e `App/ScrapsMobile`: ciclo de vida, menus e atalhos.
- `App/Shared`: ícone e cor de destaque.
- `StickyDomain`: notas, formatação portátil e ações fixas.
- `StickyStorage`: arquivos atômicos, sessões em memória e recuperação.
- `StickyEditor`: editor nativo e paleta compartilhados.
- `StickyUI`: janelas do Mac, salvamento e envio ao Notas.
- `StickyMobileUI`: biblioteca, navegação e edição no iPhone/iPad.
- `StickyIntents`: entidades do Spotlight e ações de Siri/Atalhos.
- `project.yml`: fonte do projeto Xcode.
