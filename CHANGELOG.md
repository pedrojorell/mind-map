# Histórico de versões

Todas as mudanças importantes do MapLong ficam registradas aqui.
O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e as versões seguem o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [2.1.0] — 2026-10-04

### Adicionado
- 27 formas de tópico: losango, documento, paralelogramo, círculo, processo,
  armazenamento, cilindro, cartão, guia, octógono, etiqueta, setas, balão
  de fala, estrela, gema, nuvem, nota adesiva e outras.
- Estilo do tópico: fonte, realce (marca-texto), texto justificado, canto,
  encher, cor e estilo da borda (contínua, tracejada, pontilhada); estilo,
  cor e peso da linha de cada ramo, com o novo estilo "Afunilado".
- Aplicar estilo aos tópicos do mesmo nível e redefinir estilo.
- Caixa de texto e nota adesiva.
- Estilo de página: fonte do tema, desenho à mão, fundo com textura ou
  imagem, marca d'água, ramo colorido (por ramo, uma cor, por nível,
  arco-íris), alinhar tópicos do mesmo nível e permitir sobreposição.
- 8 temas novos e "Salvar como tema personalizado".
- Relações em linha reta (Ctrl+Shift+R), contínuas ou tracejadas, com seta
  no início e/ou no fim, cor própria e opção de ficar por cima ou por baixo
  dos tópicos.
- Linha de conexão (Ctrl+J): liga um tópico flutuante a outro tópico.
- Marcadores: prioridade de 1 a 30, mais rostos, pessoas, setas, novos
  símbolos e "Usados recentemente".

### Corrigido
- Ctrl+Alt+C copiava o tópico em vez de copiar o estilo.

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
