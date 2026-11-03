# Contrato da sessão do carrinho

Integração entre a inclusão do produto (Gabriel, SCRUM-36, SCRUM-37 e SCRUM-39) e o carrinho persistido (João, SCRUM-69 e SCRUM-71). Jean aprova este contrato e revisa a integração. Este documento não altera comportamento: a `dev` continua com `ProcessCartLines` em `lib/main.dart`.

Para o envio, a confirmação e a idempotência, vale [`docs/order-integration.md`](order-integration.md). Para a inclusão e a sessão, vale este arquivo. O trecho daquele handoff que manda acrescentar a linha com `CartLines.read` e `CartLines.replace` deixa de ser o caminho das stories acima.

## Decisão

Há uma sessão por processo e um `CartRepository` dentro dela. O SQLite é a fonte persistida. A lista em memória é só o último resultado confirmado por `load`, `add`, `update` ou `remove`.

`CartLines` permanece como está. `ProcessCartLines.read` e `ProcessCartLines.replace` continuam servindo à revisão em memória e aos testes atuais. `replace` compara a sequência inteira, troca a lista e não gera `lineId`.

`replace` não é a gravação da sessão. Ele é síncrono: não espera o SQLite, não entra na fila das operações assíncronas e não atribui `lineId`. Devolver `true` depois de mudar só a memória mostraria sucesso antes da persistência. Na implementação persistida, cumprir `CartLines.replace` durante a migração significa devolver `false` sem mexer no cache nem no banco. O `CartViewModel` então relê a lista anterior: quantidade e remoção não têm efeito até passarem a chamar `updateLine` e `removeLine`. Essa troca faz parte da SCRUM-69, no mesmo passo em que `main` deixa de injetar `ProcessCartLines`.

A sessão não é um segundo carrinho ao lado de `ProcessCartLines`. Em produção existe um objeto só.

## API mínima

Assinatura ilustrativa. Não é código do app e não deve ser copiada para `lib/` neste PR.

```dart
abstract class CartSession extends ChangeNotifier {
  /// Falso até o primeiro restore() concluir. Lista vazia ainda não restaurada
  /// não é carrinho vazio.
  bool get isReady;

  /// CartRepository.load. Sucesso substitui o cache e notifica.
  Future<void> restore();

  /// Cache confirmado. Antes de isReady, falha em vez de devolver vazio.
  List<CartItem> read();

  /// CartRepository.add. O CartItem devolvido tem lineId não nulo.
  Future<CartItem> addLine({
    required String productId,
    required int quantity,
    String? note,
  });

  /// CartRepository.update na mesma lineId. Não cria outra linha.
  Future<CartItem> updateLine({
    required String lineId,
    required int quantity,
    String? note,
  });

  /// CartRepository.remove. Não apaga outra lineId.
  Future<void> removeLine(String lineId);
}
```

`read` devolve cópia imutável, na ordem de `position` do SQLite. `quantity` segue a regra de `CartItem`: inteiro maior ou igual a 1. Zerar quantidade é `removeLine`, não `updateLine`. `note` nula é ausência de observação.

Uma operação por vez, numa fila do processo. A próxima espera a anterior. O cache só muda no fim de uma operação bem-sucedida, com o valor que o repositório devolveu. `read` durante a espera devolve o último cache confirmado.

Depois de sucesso, a sessão notifica. Quem escuta descarta a projeção local e chama `read`. A projeção do `CartViewModel` não é outra fonte.

## Fonte de verdade e ciclo de vida

1. `DinnaApp` cria uma sessão com o `SqfliteCartRepository` já existente.
2. `restore()` roda antes do primeiro `CartViewModel`.
3. A tela de detalhe, quando incluir, chama `addLine` e só segue depois do `CartItem` com `lineId`.
4. A revisão chama `updateLine` e `removeLine`.
5. Fechar o processo não apaga o SQLite. A abertura seguinte repete o `restore`.

`CartRepository` já expõe `load`, `add`, `update`, `remove` e `removeConfirmed`. Este contrato usa as quatro primeiras. `removeConfirmed` fica fora das SCRUM-39 e SCRUM-71.

## Responsabilidades e arquivos

| Quem | Faz | Não faz |
| --- | --- | --- |
| Gabriel | Detalhe do produto, quantidade e observação locais, `addLine` na SCRUM-39. | Gerar `lineId`, abrir SQLite, chamar `replace` para incluir, enviar pedido. |
| João | Implementar a sessão, ligá-la no app, restaurar na abertura, notificar, migrar quantidade e remoção para `updateLine` e `removeLine`, distinguir falha de carrinho vazio. | Tela de detalhe, `lineId` fora de `CartRepository.add`. |
| Jean | Este contrato, revisão dos conflitos e compatibilidade com a intenção. A reconciliação após o 201 fica para depois. | Implementar a sessão neste PR. |

Arquivos previstos quando as stories forem implementadas:

| Arquivo | Dono |
| --- | --- |
| `lib/features/menu/product_detail_view.dart` (novo) | Gabriel |
| `lib/features/menu/menu_view.dart` | Gabriel, no toque que abre `/product` |
| `lib/features/menu/product_detail_view_model.dart` | Ninguém. Já carrega o produto e não conhece o carrinho. |
| `lib/features/client/cart/cart_session.dart` (novo) | João |
| `lib/main.dart`, `lib/app/app.dart` | João |
| `lib/features/client/cart/cart_view_model.dart` | João, na troca de `replace` por `updateLine` e `removeLine` |
| `lib/features/client/cart/cart_view.dart` | João, para espera da restauração e falha visível |
| `lib/app/router/app_router.dart` | João no construtor e no `/cart`; Gabriel só no case `/product` |
| `lib/core/domain/cart_item.dart`, `cart_repository.dart`, `sqflite_cart_repository.dart`, `cart_lines.dart` | Ninguém nestas stories |
| `order_submission_view_model.dart`, `order_intent_store.dart` | Ninguém agora. Jean coordena a reconciliação futura. |

`/product` hoje cai no `RoutePlaceholder`. O cardápio ainda não navega para o detalhe. Os dois podem editar `app_router.dart` em regiões diferentes; Jean resolve o conflito se os PRs se cruzarem. João entra primeiro com a sessão e o placeholder de `/product` intacto.

## Invariantes

- Só `CartRepository.add` gera `lineId`. A UI não escolhe o valor.
- `lineId` identifica a linha local. `CartItem.toOrderItem()` o omite. `OrderRequest.itemMaps` usa esse método, então o body de `POST /orders` não leva `lineId`.
- Duas linhas com o mesmo `productId` e a mesma `note` podem ter `lineId` diferentes. Inclusão nova não reaproveita id de linha removida.
- Não há dois carrinhos independentes em memória.
- `addLine`, `updateLine` e `removeLine` só concluem com sucesso depois que o SQLite confirma.
- Falha do SQLite não esvazia o cache, não devolve lista vazia e não mostra a alteração como feita.
- `updateLine` preserva a `lineId`. Se `update` devolver `false`, a linha não existe: a sessão recarrega e informa a ausência, sem inserir outra.
- `restore` termina antes da primeira leitura da UI, ou o consumidor espera `isReady`. `read` antes disso falha. Lista vazia só depois de um `load` bem-sucedido sem linhas.
- Produto ausente ou `available == false` é sinal da tela. A sessão não remove a linha por causa do catálogo. Falha de rede na consulta do produto também não remove.
- Mudança na sessão não chama `submit`, `resume` nem `beginAnotherOrder`.
- A sessão não lê nem grava `OrderIntentStore`.
- Nenhuma operação da sessão altera o UUID ou o body de uma intenção em andamento.

`OrderIntent.cartItems` hoje reconstrói `CartItem` sem `lineId`, e `confirmedItems` sai dessa lista. Isso não autoriza colocar `lineId` no body. A fotografia com `lineId` é requisito futuro, fora deste contrato.

## Falhas, concorrência e restauração

A fila serial impede que duas gravações apliquem fotografias velhas uma por cima da outra. Não há escrita otimista no cache: a quantidade mostrada como confirmada só muda quando `updateLine` retorna. Se a chamada falha, a projeção volta ao último `read`.

`restore` que lança deixa `isReady` falso e o cache intocado. A abertura do carrinho mostra a falha de persistência, não o estado vazio de “escolha pratos no cardápio”. Carrinho vazio é o resultado de um `load` concluído sem linhas.

`removeLine` em id já ausente termina com a sessão recarregada e sem essa linha. Exceção do banco não é ausência.

## Integração planejada com o envio

Fora da SCRUM-39 e da SCRUM-71. Não chamar `removeConfirmed` ao ligar a sessão.

Quando a reconciliação for feita, ela precisa de:

- fotografia imutável das linhas enviadas, com `lineId`, associada ao `intentId`;
- essa fotografia fora do body HTTP;
- execução só depois do sucesso da intenção gravado em disco;
- marca de “já reconciliada” na mesma transação SQLite que altera as linhas, para o reinício não descontar de novo;
- preservação de linha criada durante o POST e de linha cuja observação mudou;
- nenhuma exclusão automática quando a quantidade foi reduzida durante o envio, enquanto essa regra não for aprovada por Jean;
- falha de SQLite sem apagar a intenção e sem liberar outro POST.

O `removeConfirmed` atual subtrai a quantidade enviada e apaga a linha se o restante fica abaixo de 1. Essa regra não está aprovada para o caso de redução durante o POST. Até a reconciliação existir, o 201 não altera o carrinho. O `OrderSubmissionViewModel` e o arquivo da intenção permanecem a fonte do envio.

## Testes contratuais esperados

Na implementação, não neste PR:

- `addLine` devolve `lineId` e um `load` novo vê a mesma linha.
- Duas inclusões iguais recebem ids diferentes.
- Falha do SQLite em `addLine` deixa `read` como estava.
- `updateLine` muda quantidade e observação e mantém a `lineId`.
- `removeLine` tira só aquela linha.
- Duas chamadas concorrentes persistem as duas, sem perder a primeira.
- `read` antes de `restore` falha; depois de `restore` sem linhas, a lista vazia é legítima.
- `toOrderItem` e o body da intenção não contêm `lineId`.
- Uma operação da sessão não modifica o arquivo da intenção.

Os testes atuais de `ProcessCartLines` e do `CartViewModel` em memória continuam válidos até a migração da revisão.

## Fora do escopo

Implementação da sessão, tela de detalhe, mudança de `CartRepository`, reconciliação após HTTP 201, alteração do body idempotente e qualquer dependência nova.
