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
