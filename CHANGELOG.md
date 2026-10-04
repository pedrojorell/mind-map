# Histórico de versões

Todas as mudanças importantes do MapLong ficam registradas aqui.
O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e as versões seguem o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [2.1.0] — 2026-10-04

### Adicionado
- Licença vitalícia de R$ 69,00 com teste grátis de 7 dias. Depois do teste,
  sem licença, o MapLong fica em modo leitura: os mapas continuam abrindo,
  sendo apresentados e exportados, mas não é possível criar nem editar.
- Tela da licença (Configurações → Ativar licença): estado do teste, compra e
  ativação do código; aviso nos últimos dias do teste.
- Códigos assinados digitalmente (Ed25519) e conferidos sem internet; licença
  de proprietário com acesso total.
- Gerador de licenças do proprietário (`licencas/gerador.mjs`).
- Servidor de vendas para Cloudflare Workers: pagamento pelo Mercado Pago
  (Pix ou cartão), entrega do código na tela e por e-mail (Brevo), gerador
  on-line protegido por senha e recuperação de código pelo número do
  pagamento.
- Testes do gerador e do servidor na verificação automática do GitHub.

## [2.0.0] — 2026-10-02

Primeira versão com o nome **MapLong** (antes: PinealMap).

### Adicionado
- Nova marca: logo, ícones do Windows e da versão web, cores do tema.
- Abas como no navegador para vários mapas abertos ao mesmo tempo.
- Faixa de ferramentas (Início, Inserir, Design, Exibir), barra flutuante e
  painel lateral com abas.
- 8 estruturas: balanceado, direita, esquerda, lógico, organograma, árvore,
  linha do tempo e espinha de peixe.
- Tópicos nunca se sobrepõem: o mapa se ajusta enquanto você digita.
- 2 cliques editam o tópico; 3 cliques criam um tópico conectado.
- Imagens, documentos, arrastar e soltar arquivos, vários links (site,
  e-mail, telefone, pasta), etiquetas, comentários, marcadores e adesivos.
- Balões, limite, resumo, tabela, fórmula LaTeX e tarefas.
- Visões Esboço e Gantt (com feriados nacionais), apresentação, modo Zen,
  foco num ramo e minimapa.
- Wikipédia, imagens livres (Openverse) e tema gerado a partir de uma cor.
- Exportação para PNG, PDF, Word, CSV, HTML, Markdown, TXT, OPML e FreeMind;
  importação de Markdown, TXT, OPML e FreeMind.
- Favoritos, lixeira e histórico de versões automático.
- Arquivos `.maplong` abrem com dois cliques, numa única janela.
- Configurações (tema claro/escuro/sistema), tela Sobre, boas-vindas e aviso
  de nova versão.
- Indicador "Salvando… / Salvo / Erro ao salvar" na barra de status.
- Registro de erros em arquivo, sem fechar o app.
- A janela do Windows lembra tamanho e posição e tem tamanho mínimo.
- Instalador para Windows, publicação da versão web e verificação automática
  de cada Pull Request.

### Alterado
- Arquivos passam a usar a extensão `.maplong` (`.pmap` continua abrindo).

### Migração
- Os mapas salvos pelo PinealMap são trazidos automaticamente na primeira
  abertura do MapLong.
