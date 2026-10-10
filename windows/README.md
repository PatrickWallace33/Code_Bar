# Uso IA (Code_Bar) - Versão Windows

Companion desktop minimalista em Python + PySide6 para Windows 10 e Windows 11 com 100% de paridade visual e funcional em relação à versão macOS.

---

## ✨ Funcionalidades no Windows

- **Encaixe Magnético em 4 Bordas:** Atração magnética automática de 36px para qualquer borda da tela (**Direita**, **Esquerda**, **Topo/Cima**, **Base/Baixo**) ou modo **Flutuante**.
- **Contorno Suave em S (Curva Canônica):** Borda e curvatura idênticas e preservadas em qualquer lado da tela através de mapeamento geométrico rígido, com espessura uniforme de 54px.
- **Translucidez Inteligente:** Fundo escuro sutilmente translúcido em repouso que ganha opacidade total ao passar o mouse por cima (`hover`).
- **Anéis de Cota Diferenciados:**
  - **Claude (Anthropic):** Exibe a cota da sessão (5 horas rolantes), com opção no menu para alternar para semanal.
  - **Codex (OpenAI):** Exibe a cota semanal e contagem de reset credits.
  - **Google Antigravity:** Exibe consumo do Gemini.
- **Detecção de Sessões e Projetos Recentes:** Varredura automática e segura dos diretórios locais do Windows:
  - Claude: `%USERPROFILE%\.claude\projects`
  - Codex: `%USERPROFILE%\.codex\sessions`
  - Antigravity: `%USERPROFILE%\.gemini\antigravity-cli\brain`
- **Configuração Persistente:** Salva automaticamente a posição e preferências em `%APPDATA%\Code_Bar\settings.json`.

---

## 🚀 Como Executar

### Opção 1: Inicializador Automático (Recomendado)
Basta dar dois cliques no arquivo:
```cmd
run.bat
```
O script verifica o Python, cria o ambiente virtual isolado (`venv`), instala a biblioteca `PySide6` e executa o aplicativo em segundo plano sem janela de prompt (`pythonw`).

---

### Opção 2: Linha de Comando Manual
1. Abra o Terminal ou PowerShell nesta pasta `windows`:
```cmd
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
python code_bar.py
```

---

## 🧪 Testes Automatizados

Para executar os testes de geometria, atração magnética e modelos no Windows:
```cmd
python test_windows.py
```
