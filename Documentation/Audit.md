# Auditoria da versão 1.0.0 (5)

## Erros corrigidos

| Impacto | Falha | Correção |
| --- | --- | --- |
| Alto | Sair do Mac podia encerrar um salvamento, criação ou fechamento em andamento. | O encerramento aguarda essas operações e é cancelado se falharem ou ultrapassarem dois segundos. Os rascunhos continuam disponíveis. |
| Alto | Uma gravação antiga podia substituir uma edição mais recente. | Os armazenamentos recusam snapshots com data anterior. Fechar uma nota preserva o conteúdo mais recente na recuperação. |
| Alto | Converter uma nota de sessão podia descartar uma edição recebida durante a gravação. | As alterações da mesma nota são serializadas durante a conversão entre memória e arquivo. |
| Alto | Recuperar novamente uma nota no iOS podia substituir seu rascunho; uma ação antiga de apagar podia removê-la. | Recuperação e remoção definitiva verificam se a nota continua apagada antes de alterar o estado. |
| Médio | Substituir o app instalado podia ocorrer enquanto ele ainda executava ou antes de verificar a nova cópia. | O instalador prepara e verifica a nova cópia, aguarda o encerramento, preserva a anterior na Lixeira e restaura a instalação se houver falha. |
| Médio | Datas JSON perdiam frações de segundo, alterando ordenação e limites de recuperação. | Documentos v3 guardam a representação numérica precisa de Date, em segundos desde 2001. Arquivos v1/v2 com datas ISO continuam sendo lidos. |
| Médio | Alterar cor ou janela podia retroceder uma data de edição futura. | A data de edição permanece monotônica. |
| Médio | Ênfases sobrepostas ou limites entre partes de acentos e emoji podiam perder formatação. | A normalização combina negrito e itálico; a ponte do editor usa limites e comprimentos de escalares Unicode. |
| Médio | Um callback de compartilhamento anterior podia concluir a operação seguinte. | Cada solicitação mantém seus próprios delegates e ignora serviços de outra solicitação. |
| Médio | Ações do iOS podiam disputar folhas de ajustes, cor e recuperação. | Uma apresentação única coordena as folhas; abrir uma nota ou a biblioteca dispensa a folha anterior. |
| Médio | A busca de ações não reconhecia português quando o app estava em inglês. | As consultas e palavras-chave incluem os nomes de todas as traduções incluídas, mantendo somente quatro ações fixas. |

## Verificação

- Testes de regressão de persistência, migração, precisão, conversão, recuperação,
  encerramento e formatação Unicode.
- Verificação das tabelas de tradução: chaves, duplicações, parâmetros de
  formatação e frases de Siri com o nome do app.
- Simulação isolada do instalador: sucesso, assinatura inválida, recusa ao sair,
  processo ainda ativo e falha de registro. Nenhum app real é iniciado.
- Builds nativos e arquivos Release de Mac, iPhone e iPad no workflow.
  Verificação de recursos, privacidade, ícone, metadados de intents e sandbox
  efetivo do produto Mac; Release recusa permissão de depuração.

O arquivo assinado para a loja é verificado novamente por
Scripts/archive.sh, incluindo a identidade Apple Distribution.

## Distribuição internacional

A interface, mensagens e atalhos incluem inglês e português do Brasil, com
inglês como idioma de desenvolvimento. O texto das notas aceita Unicode,
incluindo escrita da direita para a esquerda. A interface ainda não inclui
traduções para árabe ou hebraico. Datas exibidas usam o formato do sistema;
datas armazenadas não dependem de idioma, calendário ou fuso horário.

O conteúdo permanece local e pode ser sincronizado, se habilitado, pela base
privada do CloudKit. Conflitos de texto preservam cópias recuperadas. Nenhum texto de nota entra no Spotlight. Os
backups configurados no sistema podem incluir notas persistentes.

O suporte mínimo é macOS/iOS/iPadOS 27, com Apple silicon no Mac. Conferências
de interação, VoiceOver, tamanhos de texto, idiomas e layout RTL ficam para
execução manual conforme [Validation.md](Validation.md). A publicação na loja
exige os certificados e perfis da equipe, informações comerciais aplicáveis,
URLs públicas e screenshots reais conforme [AppStore.md](AppStore.md).

## Ampliação auditada

- Migração para grupos copia arquivos sem apagar os originais ou sobrescrever
  documentos já existentes; arquivos ilegíveis continuam preservados.
- Importações do iCloud e ações de widgets comparam a versão lida antes de
  escrever. Uma edição local posterior impede a substituição.
- Notificações silenciosas no iOS têm resposta limitada a 20 segundos.
- Notas de sessão permanecem fora do disco, iCloud e widgets; duplicação conserva
  essa propriedade. Arquivo e favoritos não confundem o nível flutuante da janela.
- Campo rich text aditivo preserva a leitura dos documentos v3 anteriores;
  estilos desconhecidos caem no corpo e links de arquivos locais são rejeitados.
- Widgets usam AppEntity sem indexação de conteúdo; os quatro comandos fixos
  continuam sendo o único conjunto doado ao Spotlight.
- O shader só afeta a borda; não filtra o TextEditor. Compilação Metal é verificada
  antes dos builds, e o efeito para ao terminar ou ao entrar em segundo plano.

A comprovação de compilação e assinatura está no CI da revisão correspondente;
a comprovação do uso continua pendente das conferências manuais.
