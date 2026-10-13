# iCloud, grupos de aplicativos e Handoff

O app funciona localmente sem ativar sincronização. Para sincronizar, habilitar
**Usar iCloud** nos ajustes do Scraps em cada dispositivo e usar a mesma conta
Apple. Não existe uma conta própria do Scraps.

## Configuração da equipe

No Apple Developer e no Xcode, habilitar para o identificador
`com.joaocosta.Scraps`, nas duas plataformas:

- iCloud com CloudKit e contêiner `iCloud.com.joaocosta.Scraps`;
- notificações push, usadas pelo motor de sincronização;
- grupos de aplicativos: `33FPG9442W.com.joaocosta.Scraps` no Mac e
  `group.com.joaocosta.Scraps` no iOS.

As extensões `com.joaocosta.Scraps.widgets` usam apenas os grupos e, no Mac,
o sandbox. Configurar assinatura automática com a mesma equipe nos quatro
alvos: Scraps, ScrapsMobile, ScrapsWidgetsMac e ScrapsWidgetsMobile. O projeto
usa a equipe 33FPG9442W. Se mudar a equipe, ajustar também o identificador do
grupo Mac em StickyKitIdentity.swift.

O instalador e o arquivamento podem atualizar perfis com a conta configurada
no Xcode. Não guardam certificados ou senhas no repositório. Uma equipe pessoal
sem suporte a essas capacidades pode testar a interface no simulador, mas não
substitui os perfis necessários para testar iCloud nos aparelhos.

## Esquema CloudKit

A base é **privada**, com zona personalizada `Scraps` e tipo de registro `Scrap`.
O conteúdo, formatação, cor, etiquetas, favorito, arquivo e estado de recuperação
viajam num documento JSON portátil. Posição e opções de janela permanecem locais.

| Campo | Tipo | Uso |
| --- | --- | --- |
| `schema` | Int64 | Versão do envelope, atualmente 1 |
| `payload` | Encrypted Bytes | Documento com menos de 900 KB |
| `document` | Asset | Documento maior; CloudKit cifra assets por padrão |

Criar `payload` como campo **Encrypted**, nunca como campo comum já existente.
Não criar índices para texto, título, etiquetas ou payload. O nome do registro
é o UUID da nota; não contém o título. Após criar e testar o esquema no ambiente
Development, usar **Deploy Schema Changes** no CloudKit Console antes de
TestFlight ou distribuição. Release usa Production; Debug usa Development.
Os conteúdos e os metadados de sincronização dos dois ambientes são independentes.
Notas locais continuam disponíveis ao trocar de configuração.

O CI compila CloudKit e verifica entitlements, mas não pode provisionar a equipe,
publicar esse esquema ou provar uma sincronização com a conta do proprietário.

## Comportamento e recuperação

- A extensão do widget altera o arquivo compartilhado; o aplicativo envia
  essas alterações ao iCloud quando está em execução ou é aberto novamente.
- Notas de sessão existem apenas em memória; não entram no iCloud nem nos widgets.
- Arquivar conserva a nota e sincroniza o arquivo; no Mac fecha sua janela.
- Exclusão vai para recuperação por 30 dias. Remoção definitiva e expiração
  também são enviadas aos outros dispositivos quando a sincronização está ativa.
- Alterações independentes são combinadas. Edições concorrentes de texto são
  mantidas em uma cópia marcada **Edição recuperada**.
- Sem rede, o arquivo local continua disponível. O motor mantém estado e tenta
  novamente; o botão **Sincronizar agora** permite solicitar uma atualização.
- Trocar ou sair da conta Apple pausa a sincronização e conserva os arquivos
  locais. Reativar na nova conta envia as notas locais para essa conta.
- Desativar iCloud interrompe a sincronização; não apaga as notas já presentes
  no iCloud. Apagar notas com sincronização ativa propaga essa remoção.
- Handoff e links abrem uma nota pelo identificador, sem transportar o texto
  pelo índice. A nota precisa ter chegado ao outro dispositivo pelo iCloud.

Campos cifrados são cifrados no dispositivo. A disponibilidade das chaves
exclusivamente ao proprietário depende de **Proteção Avançada de Dados** na
conta Apple; não anunciar essa exclusividade para todas as contas.
