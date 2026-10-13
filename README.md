# Scraps

Notas adesivas para o macOS, na linha do Stickies: cada nota é uma pequena janela de vidro que fica sobre as outras, guarda sozinha o que foi digitado e pode ser enviada ao app Notas.

O app roda em App Sandbox sem nenhuma permissão adicional: as notas ficam no contêiner do próprio app e o envio ao Notas usa o serviço de compartilhamento do sistema.

## Requisitos

- macOS 27 e Xcode 27;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), para regenerar o projeto a partir de `project.yml`.

## Estrutura

- `App/Scraps/` — o app: ciclo de vida, menus e os atalhos publicados ao sistema;
- `Packages/StickyKit/` — o que o app faz, em quatro módulos independentes do projeto Xcode:
  - `StickyDomain` — o que é uma nota e o contrato de armazenamento;
  - `StickyStorage` — um arquivo por nota e o aviso de mudança;
  - `StickyUI` — as janelas, o salvamento automático e o envio ao Notas;
  - `StickyIntents` — as ações para Spotlight, Siri e Atalhos;
- `Scripts/dev-install.sh` — compila e instala em `/Applications`;
- `project.yml` — fonte do `Scraps.xcodeproj`.

## Build e testes

```sh
xcodegen generate
xcodebuild -project Scraps.xcodeproj -scheme Scraps -destination 'platform=macOS' build
swift test --package-path Packages/StickyKit
```

## Instalação local

```sh
Scripts/dev-install.sh
```

Spotlight, Siri e Atalhos leem a cópia registrada em `/Applications`, por isso as ações do app só ficam disponíveis depois da instalação.

## Estado

Versão 0.1.0, em desenvolvimento inicial.
