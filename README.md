# PinealMap 🌲

Aplicativo de **mapas mentais** que roda localmente (Windows, macOS, Linux ou no
navegador), funciona offline e salva seus documentos.

## Como rodar

Pré-requisito: [Flutter](https://docs.flutter.dev/get-started/install) 3.32 ou mais novo.

```bash
flutter pub get

# Desktop (recomendado — salva arquivos .pmap direto no disco)
flutter run -d windows   # ou: -d macos / -d linux

# Navegador
flutter run -d chrome
```

Para gerar um executável:

```bash
flutter build windows    # build/windows/x64/runner/Release/
flutter build macos      # build/macos/Build/Products/Release/
flutter build linux      # build/linux/x64/release/bundle/
flutter build web        # build/web/ (sirva com qualquer servidor estático)
```

> No Linux é preciso ter `clang cmake ninja-build pkg-config libgtk-3-dev`.

## Como seus mapas são salvos

- **Salvamento automático**: toda alteração vai para a biblioteca local do app
  (tela inicial → “Meus mapas”). Nada se perde ao fechar.
- **Arquivos `.pmap`**: `Ctrl+S` salva o mapa em um arquivo (JSON legível).
  No desktop, depois do primeiro “Salvar como”, o `Ctrl+S` regrava no mesmo
  arquivo; um `•` no título indica alterações ainda não gravadas no arquivo.
  No navegador o arquivo é baixado.
- **Abrir arquivo** (tela inicial) importa um `.pmap` para a biblioteca.
- **Exportar**: imagem PNG (`Ctrl+E`) e Markdown (menu ⋮).

## Recursos

- Modelos: em branco, clássico, brainstorm, projeto, estudo e SWOT
- Tópicos, subtópicos e tópicos flutuantes (duplo clique no fundo)
- Edição direto no mapa: comece a digitar, `F2`, `Espaço` ou duplo clique
- Arrastar e soltar: solte um tópico sobre outro para mudar de pai
- Organização automática (balanceada) ou posição livre
- Recolher/expandir ramos, busca (`Ctrl+F`), zoom e “ajustar à tela”
- Cores, preenchimento, formas, fonte, negrito/itálico, borda tracejada
- Estilos de conector (curvo, reto, cotovelo)
- Anotações, links e anexos de arquivo (desktop) em cada tópico
- Copiar/colar ramos; colar texto com recuo ou listas vira tópicos
- Desfazer/refazer (até 100 passos)
- Tema claro e escuro

## Atalhos

| Tecla | Ação |
|---|---|
| `Tab` | Novo subtópico |
| `Enter` | Novo tópico irmão |
| `F2` / `Espaço` / digitar | Editar texto (`Enter` confirma, `Shift+Enter` quebra linha, `Esc` cancela) |
| `Del` / `Backspace` | Excluir tópico |
| Setas | Navegar entre tópicos |
| `Alt+↑` / `Alt+↓` | Reordenar entre irmãos |
| `/` | Recolher/expandir ramo |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copiar / recortar / colar |
| `Ctrl+Z` / `Ctrl+Y` | Desfazer / refazer |
| `Ctrl+L` | Organizar mapa |
| `Ctrl+0` | Ajustar à tela |
| `Ctrl +` / `Ctrl -` | Zoom |
| `Ctrl+F` | Buscar |
| `Ctrl+S` / `Ctrl+Shift+S` | Salvar / Salvar como |
| `Ctrl+E` | Exportar PNG |

## Estrutura do código

```
lib/
  main.dart               app e tema
  models.dart             MindMapDoc / MindMapNode (+ JSON)
  library.dart            biblioteca local e salvamento automático
  editor_controller.dart  seleção, histórico e operações do editor
  layout.dart             organização automática
  file_actions.dart       salvar/abrir .pmap, exportar PNG e Markdown
  templates.dart          modelos de mapa
  io/                     leitura/gravação de arquivos (desktop x web)
  screens/                tela inicial e editor
  widgets/                canvas, nós e painel de propriedades
test/widget_test.dart     testes
```

Rodar os testes: `flutter test`
