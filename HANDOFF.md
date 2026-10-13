# Scraps — desenvolvimento e validação

Atualizado em 13/10/2026. Desenvolvimento diretamente na `main`, com commits por funcionalidade. Versão em preparação: 1.0.0 (4), macOS 27 e iOS/iPadOS 27.

## Funcionalidades integradas

- Notas persistentes e notas de sessão em memória; salvamento ordenado, recuperação por 30 dias e preservação de arquivos ilegíveis.
- App universal nativo, cores adaptativas, editor compartilhado, recolhimento, janelas flutuantes, Spaces e atalho global no Mac.
- Quatro ações fixas no Spotlight; o conteúdo das notas não é indexado. Interface em inglês e português brasileiro.
- Armazenamento compartilhado com migração que preserva os originais, favoritos, etiquetas, arquivo e duplicação no modelo de dados.
- Sincronização opcional pela base privada do CloudKit, resolução de conflitos com cópias recuperadas, Handoff e links para notas entre plataformas.
- Instalação com proteção da versão anterior; preparação de arquivos Release para as duas plataformas.

## Registro por funcionalidade

### Integração na main

O histórico de implementação e auditoria foi integrado sem reescrita. Corrigida a importação do domínio no suporte a Handoff. Widgets, formatação ampliada, organização e animação ainda estão em implementação.

## Validação

As regras portáveis passam em Linux. Compilação e validação dos produtos com SDKs Apple são feitas no CI; a ampliação ainda não está aprovada por esse CI. Testes visuais, uso em dispositivos, Spotlight, sincronização real e distribuição com certificados ficam para o proprietário.

## Pendências de publicação

Concluir a ampliação, passar o CI nativo e atualizar a documentação. A distribuição exige perfis com CloudKit, notificações e grupos de aplicativos, esquema CloudKit em produção, URLs de suporte/privacidade e capturas reais. Não houve publicação na App Store.

### Formatação ampliada

Editor nativo com título, cabeçalho, legenda, código, sublinhado, tachado, destaque e links, além das listas e caixas de marcar. A representação portátil preserva Unicode e os documentos antigos; links de arquivos locais são excluídos. Acrescentadas verificações de compatibilidade, preservação na edição de listas e conversão nativa. Validação com SDK Apple em andamento.

### Animação Metal

Borda animada por shader Metal ao criar uma nota ou trocar sua cor. O editor nativo continua independente do efeito. A animação termina em 850 ms, pausa em segundo plano e respeita movimento reduzido, transparência reduzida, contraste e economia de energia. Corrigida também a disponibilidade do atributo de previsão do Handoff no Mac. Validação nativa em andamento.

### Widgets nativos

Extensões WidgetKit para Mac, iPhone e iPad com nota configurável e captura rápida. Caixas de marcar são interativas e recusam alterações quando o texto mudou desde a renderização. Notas de sessão e arquivadas ficam fora dos widgets; atualizações usam o armazenamento compartilhado e o conteúdo é marcado como sensível. O aplicativo precisa ser aberto uma vez antes de adicionar widgets. Compilação e assinatura das extensões em validação.

### Diagnóstico da compilação Metal

O CI passa a verificar o compilador e compilar o shader isoladamente antes do pacote, para tornar visíveis erros que o executor do pacote omite. Ainda não há confirmação de build da ampliação.

### Integração concorrente e ferramenta Metal

Incorporada a alteração remota dos esquemas do Xcode sem remover as funcionalidades recentes e sem reescrever o histórico. Os esquemas são regenerados a partir de project.yml. Identificado que o executor nativo não possui Metal Toolchain; o CI passa a instalar o componente oficial quando necessário. No Xcode local, instalar em Settings > Components se solicitado.

### Disponibilidade da formatação

A compilação Metal passou após instalar o componente oficial. Ajustado o conjunto de fontes para o tipo exigido pelo SDK 27. A branch antiga foi removida localmente e no remoto; resta apenas main.

### Organização no iPhone e iPad

Favoritos, arquivo, etiquetas, busca por etiquetas e duplicação disponíveis na biblioteca e no editor. A duplicação de notas de sessão permanece em memória. O compartilhamento RTF passou a usar a mesma conversão do Mac, preservando os novos estilos. Uma edição concorrente vinda de um widget mantém o rascunho móvel como cópia recuperada. Acrescentados testes dessas regras.

### Biblioteca e organização no Mac

Biblioteca nativa com três colunas, busca, favoritos, etiquetas, arquivo, prévia formatada e compartilhamento. Acesso em Janela > Suas notas (⌘0) e pelo widget. Notas arquivadas permanecem salvas e não abrem janelas flutuantes. Metadados de uma nota em edição usam a fila de salvamento do editor. Remoções externas preservam rascunhos como cópias; falhas permitem guardar a edição separadamente. Acrescentado teste dessa recuperação.

### Limites da sincronização em segundo plano

A notificação silenciosa no iOS responde em até 20 segundos, dentro do limite do sistema, sem abandonar o estado do motor de sincronização. Arquivos temporários de anexos grandes são removidos depois da confirmação de envio. A validação real de contas, rede e notificações continua no roteiro manual.

### Preparação internacional e documentação

Atualizados os textos em inglês/português e os roteiros de publicação, privacidade, widgets, animação, organização e continuidade. Documentados os grupos, contêiner, esquema privado, campos cifrados e separação Development/Production do CloudKit. A distribuição continua dependente de perfis, esquema em produção, URLs públicas e capturas reais do proprietário.

### Identidade e verificação dos produtos

Nomes dos produtos explícitos para manter os esquemas e a incorporação de widgets coerentes com os executáveis reais. Verificação inclui extensões, idiomas, privacidade, versão, biblioteca Metal e capacidades efetivamente assinadas de grupos, CloudKit e notificações. Instalação e arquivo permitem atualizar perfis pela conta do Xcode.

### Integração dos widgets no SDK 27

Os testes nativos do pacote passaram. Corrigida a importação explícita exigida pelos botões interativos dos widgets. O shader recebe uma cópia do estado de ativação, evitando acesso ao estado da interface por uma closure concorrente. Builds completos em validação.
