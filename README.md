# Uso IA (Code_Bar)

Barra flutuante minimalista e elegante para macOS que monitora em tempo real o uso de cotas e limites das principais IAs de código:

- **Claude** (Anthropic)
- **Codex / OpenAI**
- **Google Antigravity**

O app flutua sobre qualquer aplicativo, exibindo anéis de progresso, percentuais de uso, tempo para renovação de cota e acesso rápido para retomar projetos recentes. O fundo fica semitransparente em repouso e ganha opacidade ao passar o mouse, abrir o painel ou arrastar. Ícones e percentuais continuam nítidos. O contorno tem pontas afiladas e curvas alongadas em S junto à borda direita.

---

## ✨ Funcionalidades

- **Barra como a referência:** Fundo escuro translúcido, anéis amarelos, logos brancos e indicadores compactos. O indicador prioriza o consumo semanal; o menu permite selecionar o consumo da sessão.
- **Cotas e renovação:** Consulta a cada 5 minutos, atualização manual e indicação de dados da última consulta quando houver falha.
- **Painel lateral:** Limites, tempo de renovação, resets disponíveis e validade informada pelo provedor.
- **Atividade local:** Total de tokens dos últimos 30 dias, pico diário, uso de hoje e gráfico por dia, lidos pelo CodexBar nos históricos locais disponíveis.
- **Posição persistente:** Salva a última posição e o monitor após cada movimento, inclusive arrastes feitos pelo AppKit. Restaura esse local ao reabrir.
- **Visibilidade:** Fica disponível em qualquer aplicativo e espaço de trabalho. O menu oferece a opção de acompanhar apenas o Orca.
- **Projetos Recentes:** Histórico das últimas sessões usadas em cada assistente, com atalho para copiar Resume ID ou reabrir diretamente no Terminal / VS Code.
- **Alertas de Limite:** Notificações nativas do macOS ao atingir 80%, 90% e 95% de consumo.
- **Design Nativo & Dark Mode:** Interface desenvolvida 100% em SwiftUI e AppKit, rápida e leve.

---

## 📋 Pré-requisitos

- **macOS:** 14.0 (Sonoma) ou superior
- **CodexBar:** Aplicativo instalado em `/Applications/CodexBar.app` (utilizado para consulta local das cotas)
- **Swift:** Swift 5.10 ou superior (Xcode Command Line Tools)

---

## 🚀 Como Compilar e Instalar

Clone o repositório:

```bash
git clone https://github.com/PatrickWallace33/Code_Bar.git
cd Code_Bar
```

Para compilar:
```bash
./build.sh
```

Para compilar, instalar em `/Applications` e abrir automaticamente:
```bash
./build.sh --install
```

## Controles

- Passe o mouse sobre a barra para vê-la com opacidade normal e sobre um indicador para consultar o uso.
- Clique para manter o painel aberto; clique novamente ou pressione Esc para fechar.
- Arraste a barra para reposicioná-la. Perto da borda direita, ela se encaixa automaticamente.
- Use o botão direito para alternar entre consumo semanal e da sessão, atualizar e ajustar as opções do app.

O gráfico representa tokens registrados localmente nos últimos 30 dias. Ele aparece quando o CodexBar fornece esse histórico. Resets e expiração são exibidos quando disponíveis na conta.

## Verificação

```bash
./test.sh
./build.sh
```

As verificações de cotas, resets, agregação diária e restauração da posição funcionam com Xcode Command Line Tools, sem exigir o Xcode completo.

---

## 🛠️ Tecnologias

- **Swift** & **SwiftUI**
- **AppKit** (NSPanel, NSWorkspace, ServiceManagement)
- **Swift Package Manager (SPM)**

---

## 📄 Licença

Distribuído sob a licença MIT.
