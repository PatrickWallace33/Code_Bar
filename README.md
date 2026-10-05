# Uso IA (Code_Bar)

Barra flutuante minimalista e elegante para macOS que monitora em tempo real o uso de cotas e limites das principais IAs de código:

- 🔵 **Claude** (Anthropic)
- 🟢 **Codex / OpenAI**
- 🟣 **Google Antigravity**

O app fica discretamente acoplado à janela do **Orca** (ou à borda da tela), exibindo anéis de progresso, percentuais de uso, tempo para renovação de cota e acesso rápido para retomar projetos recentes diretamente no Terminal ou VS Code.

---

## ✨ Funcionalidades

- **Monitoramento em Tempo Real:** Cotas de sessão (5h, diárias) e semanais com tempo estimado para renovação.
- **Acompanhamento do Orca:** Move-se e ajusta-se automaticamente com a janela do aplicativo Orca.
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

---

## 🛠️ Tecnologias

- **Swift** & **SwiftUI**
- **AppKit** (NSPanel, NSWorkspace, ServiceManagement)
- **Swift Package Manager (SPM)**

---

## 📄 Licença

Distribuído sob a licença MIT.
