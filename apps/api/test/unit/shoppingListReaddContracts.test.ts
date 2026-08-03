import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  ShoppingListReaddContractValidationError,
  shoppingListReaddLimits,
  validateShoppingListReaddMatchPlan,
  type ShoppingListReaddCandidateSnapshot,
} from '../../src/services/shopping/shoppingListReaddContracts.js';

const candidates: ShoppingListReaddCandidateSnapshot[] = [
  { itemId: 14, itemVersion: 8, name: 'Iced Coffee', brand: 'Stok', purchased: true, quantity: 1 },
  { itemId: 22, itemVersion: 4, name: 'Eggs', purchased: true, quantity: 1 },
  { itemId: 23, itemVersion: 2, name: 'Egg Cups', purchased: true, quantity: 1 },
];

test('AI Shopping re-add contract fixture selects Iced Coffee and Eggs, not Egg Cups', () => {
  const plan = validateShoppingListReaddMatchPlan({
    operations: [
      { requestIndex: 0, requestedText: '2 coffees', itemId: 14, quantity: 2, matchKind: 'semantic' },
      { requestIndex: 1, requestedText: 'eggs', itemId: 22, matchKind: 'exact' },
    ],
    unmatched: [],
  }, candidates, 2);

  assert.deepEqual(plan.operations.map((operation) => operation.itemId), [14, 22]);
  assert.equal(plan.operations[0]?.quantity, 2);
  assert.equal(plan.operations.some((operation) => operation.itemId === 23), false);
});

test('AI Shopping re-add contract rejects malformed or unsafe matcher plans', () => {
  assert.throws(
    () => validateShoppingListReaddMatchPlan({
      operations: [
        { requestIndex: 0, requestedText: '2 coffees', itemId: 14, quantity: 0, matchKind: 'semantic' },
      ],
      unmatched: [],
    }, candidates, 2),
    ShoppingListReaddContractValidationError,
  );
  assert.throws(
    () => validateShoppingListReaddMatchPlan({
      operations: [
        { requestIndex: 0, requestedText: 'coffee', itemId: 14, matchKind: 'semantic' },
        { requestIndex: 1, requestedText: 'iced coffee', itemId: 14, matchKind: 'semantic' },
      ],
      unmatched: [],
    }, candidates, 2),
    ShoppingListReaddContractValidationError,
  );
  assert.throws(
    () => validateShoppingListReaddMatchPlan({
      operations: [{ requestIndex: 0, requestedText: 'milk', itemId: 999, matchKind: 'semantic' }],
      unmatched: [],
    }, candidates, 1),
    ShoppingListReaddContractValidationError,
  );
  assert.throws(
    () => validateShoppingListReaddMatchPlan({
      operations: [{ requestIndex: 0, requestedText: 'eggs', itemId: 22, matchKind: 'future_match_kind' }],
      unmatched: [],
    }, candidates, 1),
    ShoppingListReaddContractValidationError,
  );
  assert.throws(
    () => validateShoppingListReaddMatchPlan({ operations: [], unmatched: [] }, candidates, shoppingListReaddLimits.maxRequestedPhrases + 1),
    ShoppingListReaddContractValidationError,
  );
});
