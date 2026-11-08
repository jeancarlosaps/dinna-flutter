# Contrato da sessão do carrinho

Contrato da inclusão do produto (SCRUM-39) e do carrinho persistido (SCRUM-69/71). A implementação está integrada em `dev`: `main` injeta `CartSession(SqfliteCartRepository())`, `DinnaApp` inicia `restore()` na abertura e a sessão libera o carrinho depois de carregar o SQLite. A revisão consulta o catálogo atual ao criar o `CartViewModel`, identificando itens indisponíveis ou ausentes.

Para o envio, a confirmação e a idempotência, vale [`docs/order-integration.md`](order-integration.md). Para a inclusão e a sessão, vale este arquivo. O trecho daquele handoff que manda acrescentar a linha com `CartLines.read` e `CartLines.replace` deixa de ser o caminho das stories acima.

## Decisão

Há uma sessão por processo e um `CartRepository` dentro dela. O SQLite é a fonte persistida. A lista em memória é projeção desse banco e só muda depois que a operação confirma. `load` devolve as linhas e `add` devolve o `CartItem` gravado. `update` e `remove` devolvem `Future<bool>`, não uma linha nem uma lista; a sessão não trata esse booleano como se fosse o estado novo do carrinho.

`CartLines` permanece como caminho compatível em memória. `ProcessCartLines.read` e `ProcessCartLines.replace` servem a fluxos sem sessão e aos testes desse modo. Em produção, `CartViewModel.persisted` usa `CartSession`; a lista publicada pela sessão é sempre derivada de operações confirmadas pelo SQLite.

`replace` não grava na sessão: é síncrono, não espera o SQLite, não entra na fila assíncrona e não atribui `lineId`. Por isso, a revisão persistida usa `updateLine` e `removeLine`; a implementação de `CartLines` fica restrita ao modo em memória.

A sessão não é um segundo carrinho ao lado de `ProcessCartLines`. Em produção existe um objeto só.

## API mínima

Resumo da API implementada em `lib/features/client/cart/cart_session.dart`.

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

  /// CartRepository.update devolve bool. true: devolve o CartItem aplicado
  /// no cache, com a mesma lineId. false: não devolve item.
  Future<CartItem> updateLine({
    required String lineId,
    required int quantity,
    String? note,
  });

  /// CartRepository.remove devolve bool. true: a linha saiu do cache.
  /// false: a chamada não é sucesso de remoção.
  Future<void> removeLine(String lineId);
}
```

`read` devolve cópia imutável, na ordem de `position` do SQLite. `quantity` segue a regra de `CartItem`: inteiro maior ou igual a 1. Zerar quantidade é `removeLine`, não `updateLine`. `note` nula é ausência de observação.

### Semântica de cada operação

As assinaturas reais de `CartRepository` permanecem. A sessão é quem traduz o resultado para o cache.

`restore` chama `load`. Só depois da leitura bem-sucedida substitui o cache, marca a sessão pronta e notifica. Exceção deixa o cache como estava e `isReady` falso. Falha de leitura não é carrinho vazio. Lista vazia só é publicada quando `load` conclui sem linhas.

`addLine` espera `add`. O `CartItem` devolvido pelo repositório, já com `lineId`, entra no cache. A notificação vem depois disso. Exceção não altera o cache e não notifica.

`updateLine` usa a linha do cache com aquela `lineId`. O `CartItem` enviado a `update` conserva essa `lineId` e o `productId` do cache, com a quantidade e a observação pedidas. O repositório responde `bool`.

- `true`: essa alteração entra no cache no lugar da linha anterior. `updateLine` devolve esse `CartItem` e só então notifica.
- `false`: o cache não recebe essa alteração. A sessão não devolve `CartItem`. Trata a linha como ausente e faz `load`. Se o `load` conclui, o cache passa a ser essa leitura e a notificação é da releitura, não de uma atualização bem-sucedida. Se o `load` falha, a exceção segue e o cache anterior permanece.
- Exceção de `update`: o cache permanece, não há notificação e a exceção chega a quem chamou.

`removeLine` espera `remove`.

- `true`: a linha daquela `lineId` sai do cache e a sessão notifica. O futuro conclui.
- `false`: não há notificação de remoção bem-sucedida e o futuro não conclui como sucesso. A sessão faz `load`. Leitura concluída publica o cache recarregado; falha de leitura preserva o cache anterior e propaga a exceção.
- Exceção de `remove`: cache intocado, sem notificação, exceção propagada.

Não há escrita otimista. Uma operação espera a anterior. `read` no meio da espera devolve o último cache confirmado. O cache não é uma segunda lista independente: cada publicação vem de `load`, do item devolvido por `add` ou da alteração que `update`/`remove` acabou de confirmar com `true`.

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
| Gabriel | Detalhe do produto, quantidade local e chamada de `addLine` na SCRUM-39. | Gerar `lineId`, abrir SQLite, chamar `replace` para incluir, enviar pedido. |
| João | Sessão persistida, restauração na abertura, publicação após confirmação do repositório e revisão por `updateLine`/`removeLine`. | Tela de detalhe, `lineId` fora de `CartRepository.add`. |
| Jean | Contrato, revisão dos conflitos e compatibilidade com a intenção. A reconciliação após o 201 fica para depois. | Alterar o body idempotente nesta integração. |

Arquivos envolvidos na integração:

| Arquivo | Dono |
| --- | --- |
| `lib/features/menu/product_detail_view.dart` | Gabriel, detalhe em bottom sheet |
| `lib/features/menu/menu_view.dart` | Gabriel, cardápio e chamada de `CartSession.addLine` |
| `lib/features/menu/product_detail_view_model.dart` | Ninguém. Já carrega o produto e não conhece o carrinho. |
| `lib/features/client/cart/cart_session.dart` | João, sessão e fila de persistência |
| `lib/main.dart`, `lib/app/app.dart` | João, composição e restauração no arranque |
| `lib/features/client/cart/cart_view_model.dart` | João, revisão persistida e compatibilidade em memória |
| `lib/features/client/cart/cart_view.dart` | João, espera da restauração e falha visível |
| `lib/app/router/app_router.dart` | João, injeta a sessão no cardápio e no carrinho |
| `lib/core/domain/cart_item.dart`, `cart_repository.dart`, `sqflite_cart_repository.dart`, `cart_lines.dart` | Contratos e armazenamento usados pela sessão ou pelo fluxo compatível |
| `order_submission_view_model.dart`, `order_intent_store.dart` | Ninguém agora. Jean coordena a reconciliação futura. |

O detalhe abre como bottom sheet sobre o cardápio; `/product` continua sendo uma rota placeholder separada. `AppRouter` passa a sessão tanto ao cardápio quanto à revisão do carrinho.

## Invariantes

- Só `CartRepository.add` gera `lineId`. A UI não escolhe o valor.
- `lineId` identifica a linha local. `CartItem.toOrderItem()` o omite. `OrderRequest.itemMaps` usa esse método, então o body de `POST /orders` não leva `lineId`.
- Duas linhas com o mesmo `productId` e a mesma `note` podem ter `lineId` diferentes. Inclusão nova não reaproveita id de linha removida.
- Não há dois carrinhos independentes em memória.
- `addLine`, `updateLine` e `removeLine` só concluem com sucesso depois que o SQLite confirma.
- Falha do SQLite não esvazia o cache, não devolve lista vazia e não mostra a alteração como feita.
- `updateLine` preserva a `lineId`. O `CartItem` devolvido existe só quando `update` retorna `true`. Com `false`, não há item publicado e a sessão recarrega.
- `restore` termina antes da primeira leitura da UI, ou o consumidor espera `isReady`. `read` antes disso falha. Lista vazia só depois de um `load` bem-sucedido sem linhas.
- Produto ausente ou `available == false` é sinal da tela. A sessão não remove a linha por causa do catálogo. Falha de rede na consulta do produto também não remove.
- Mudança na sessão não chama `submit`, `resume` nem `beginAnotherOrder`.
- A sessão não lê nem grava `OrderIntentStore`.
- Nenhuma operação da sessão altera o UUID ou o body de uma intenção em andamento.

`OrderIntent.cartItems` hoje reconstrói `CartItem` sem `lineId`, e `confirmedItems` sai dessa lista. Isso não autoriza colocar `lineId` no body. A fotografia com `lineId` é requisito futuro, fora deste contrato.

## Falhas, concorrência e restauração

A fila e a publicação do cache estão na semântica de cada operação. A quantidade confirmada na tela só muda depois de `update` retornar `true`. Exceção não anuncia sucesso.

`restore` que lança deixa `isReady` falso e o cache intocado. A abertura do carrinho mostra a falha de persistência, não o estado vazio de “escolha pratos no cardápio”. Carrinho vazio é o resultado de um `load` concluído sem linhas.

`remove` com `false` não é remoção bem-sucedida. A releitura pode mostrar a linha ausente, e a exceção do banco continua diferente dessa ausência.

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

## Verificação do contrato

Estes comportamentos descrevem os invariantes que os testes da sessão devem preservar:

- `addLine` devolve `lineId` e um `load` novo vê a mesma linha.
- Duas inclusões iguais recebem ids diferentes.
- Falha do SQLite em `addLine` deixa `read` como estava.
- `update` com `true` faz `updateLine` devolver o `CartItem` aplicado no cache, com a mesma `lineId`.
- `update` com `false` não publica a alteração pedida; a sessão recarrega e a chamada não devolve item.
- `remove` com `true` tira só aquela `lineId` e notifica.
- `remove` com `false` não conclui como remoção bem-sucedida.
- Duas chamadas concorrentes persistem as duas, sem perder a primeira.
- `read` antes de `restore` falha; depois de `restore` sem linhas, a lista vazia é legítima.
- `toOrderItem` e o body da intenção não contêm `lineId`.
- Uma operação da sessão não modifica o arquivo da intenção.

Os testes de `ProcessCartLines` e do `CartViewModel` em memória cobrem o caminho compatível. O estado persistido e as operações serializadas são cobertos em `test/features/client/cart/cart_session_test.dart` e nos testes de carrinho relacionados.

## Fora do escopo

Reconciliação do carrinho após HTTP 201, alteração do body idempotente e dependências novas.
