# banho_dormir

Um sistema (script) para servidores FiveM desenvolvido para gerir mecânicas de imersão e necessidades de Roleplay, focado nas ações de tomar banho e dormir. O script inclui lógica do lado do cliente (client-side), do lado do servidor (server-side), ficheiros de configuração e uma interface gráfica.

## 🚀 Funcionalidades

- **Sistema de Banho**: Permite aos jogadores interagir com locais específicos (chuveiros) para limpar a sua personagem.
- **Sistema de Dormir**: Mecânica para deitar/dormir em camas, ideal para recuperar energia ou para fins de interpretação (roleplay).
- **Interface Web (UI)**: Interface HTML/CSS/JS integrada para exibir barras de progresso ou menus de interação ao utilizar as funções.
- **Configuração Flexível**: Ficheiro `config.lua` simplificado para adicionar facilmente novas coordenadas de camas/chuveiros e ajustar tempos/animações.
- **Base de Dados**: Inclui estrutura SQL para guardar o estado ou as estatísticas de higiene/sono dos utilizadores (se aplicável).

O script conta com um sistema dinâmico de feedback visual baseado no estado de higiene do cidadão:

* **Efeito de Moscas (Sujeira Extrema):** Quando o nível de higiene do jogador atinge o limite mínimo, partículas de moscas começam a rodear o corpo do personagem, acompanhadas por uma fumaça/névoa verde de odor.
* **Limpeza Completa (Banho):** Ao entrar no chuveiro e iniciar a ação de banho, todas as partículas de moscas e odores são removidos instantaneamente do modelo do personagem, redefinindo o status na base de dados.
* **Desmaio por Sono (Opcional):** Caso o jogador fique muito tempo sem dormir, a tela começará a borrar (efeito de tontura) e o personagem poderá desmaiar/cair no chão até que seja levado a uma cama.

## 📁 Estrutura do Projeto

```text
banho_dormir/
├── client-side/
│   └── core.lua         # Lógica de interações, animações e comandos do cliente
├── server-side/
│   └── core.lua         # Validações, salvamento na DB e sincronização com o servidor
├── web-side/
│   ├── index.html       # Interface visual do sistema (UI)
│   └── script.js        # Lógica de exibição e comunicação (NUI)
├── config.lua           # Configurações gerais do script (coordenadas, tempos)
├── fxmanifest.lua       # Manifesto de definição do recurso para o FiveM
└── banho_dormir.sql     # Estrutura de tabelas necessárias para a base de dados
