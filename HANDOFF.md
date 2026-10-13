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
