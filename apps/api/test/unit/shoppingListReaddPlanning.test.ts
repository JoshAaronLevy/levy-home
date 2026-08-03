import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  buildShoppingListReaddMatchContext,
  normalizeShoppingListReaddText,
  validateShoppingListReaddMatchPlanForRequest,
} from '../../src/services/shopping/shoppingListReaddPlanning.js';
import { ShoppingListReaddContractValidationError, type ShoppingListReaddCandidateSnapshot } from '../../src/services/shopping/shoppingListReaddContracts.js';

const candidates: ShoppingListReaddCandidateSnapshot[] = [
  { itemId: 14, itemVersion: 8, name: 'Iced Coffee', brand: 'Stok', notes: 'Keep chilled', purchased: true, quantity: 1 },
  { itemId: 22, itemVersion: 4, name: 'Eggs', purchased: true, quantity: 1 },
  { itemId: 23, itemVersion: 2, name: 'Egg Cups', notes: 'Breakfast cups', purchased: false, quantity: 1 },
  { itemId: 24, itemVersion: 3, name: 'Chocolate Chips', brand: 'Ghirardelli', purchased: true, quantity: 1 },
  { itemId: 25, itemVersion: 2, name: 'Muffins', notes: 'School snack', purchased: true, quantity: 1 },
];

function planFor(requestText: string, operations: unknown[], unmatched: unknown[] = []) {
  return validateShoppingListReaddMatchPlanForRequest(
    { operations, unmatched },
    buildShoppingListReaddMatchContext(requestText, candidates),
  );
}

test('normalization and candidate aliases preserve useful household matching cues', () => {
  const context = buildShoppingListReaddMatchContext('Add Stok coffee and school muffins', candidates);
  assert.deepEqual(context.phrases.map(({ text, matchingText }) => ({ text, matchingText })), [
    { text: 'Stok coffee', matchingText: 'stok coffee' },
    { text: 'school muffins', matchingText: 'school muffins' },
  ]);
  assert.equal(normalizeShoppingListReaddText('  Café—Muffins! '), 'cafe muffins');
  assert.deepEqual(context.candidates[0]?.aliases, ['iced coffee', 'stok iced coffee', 'iced coffee stok', 'iced coffee keep chilled']);
  assert.ok(context.candidates[4]?.aliases.includes('muffins school snack'));
});

test('exact Eggs, exact Egg Cups, and singular/plural variants get the required match kinds', () => {
  const eggs = planFor('Add eggs', [
    { requestIndex: 0, requestedText: 'eggs', itemId: 22, matchKind: 'semantic' },
  ]);
  assert.deepEqual(eggs.operations[0], { requestIndex: 0, requestedText: 'eggs', itemId: 22, matchKind: 'exact' });

  const eggCups = planFor('Add egg cups', [
    { requestIndex: 0, requestedText: 'egg cups', itemId: 23, matchKind: 'semantic' },
  ]);
  assert.equal(eggCups.operations[0]?.matchKind, 'exact');

  const singular = planFor('Add egg', [
    { requestIndex: 0, requestedText: 'egg', itemId: 22, matchKind: 'exact' },
  ]);
  assert.equal(singular.operations[0]?.matchKind, 'normalized');
});

test('an exact candidate prevents a looser Egg Cups selection, while coffee remains a permitted semantic match', () => {
  assert.throws(
    () => planFor('Add eggs', [{ requestIndex: 0, requestedText: 'eggs', itemId: 23, matchKind: 'semantic' }]),
    ShoppingListReaddContractValidationError,
  );

  const coffee = planFor('Add coffee', [
    { requestIndex: 0, requestedText: 'coffee', itemId: 14, matchKind: 'semantic' },
  ]);
  assert.equal(coffee.operations[0]?.matchKind, 'semantic');

  assert.throws(
    () => planFor('Add bananas', [{ requestIndex: 0, requestedText: 'bananas', itemId: 14, matchKind: 'semantic' }]),
    ShoppingListReaddContractValidationError,
  );
});

test('brand and notes cues remain usable, and already-needed candidates are still eligible for planning', () => {
  const brandedCoffee = planFor('Add Stok coffee', [
    { requestIndex: 0, requestedText: 'Stok coffee', itemId: 14, matchKind: 'semantic' },
  ]);
  assert.equal(brandedCoffee.operations[0]?.itemId, 14);

  const notedMuffins = planFor('Add school muffins', [
    { requestIndex: 0, requestedText: 'school muffins', itemId: 25, matchKind: 'semantic' },
  ]);
  assert.equal(notedMuffins.operations[0]?.itemId, 25);

  const alreadyNeeded = planFor('Add egg cups', [
    { requestIndex: 0, requestedText: 'egg cups', itemId: 23, matchKind: 'exact' },
  ]);
  assert.equal(candidates.find((candidate) => candidate.itemId === alreadyNeeded.operations[0]?.itemId)?.purchased, false);
});

test('explicit numeric and written quantities are set exactly, while no quantity is preserved', () => {
  const numeric = planFor('Add 2 coffees', [
    { requestIndex: 0, requestedText: '2 coffees', itemId: 14, quantity: 2, matchKind: 'semantic' },
  ]);
  assert.equal(numeric.operations[0]?.quantity, 2);

  const written = planFor('Add twenty one chocolate chips', [
    { requestIndex: 0, requestedText: 'twenty one chocolate chips', itemId: 24, quantity: 21, matchKind: 'semantic' },
  ]);
  assert.equal(written.operations[0]?.quantity, 21);

  const absent = planFor('Add coffee', [
    { requestIndex: 0, requestedText: 'coffee', itemId: 14, matchKind: 'semantic' },
  ]);
  assert.equal(absent.operations[0]?.quantity, undefined);
  assert.throws(
    () => planFor('Add coffee', [{ requestIndex: 0, requestedText: 'coffee', itemId: 14, quantity: 2, matchKind: 'semantic' }]),
    ShoppingListReaddContractValidationError,
  );
});

test('punctuation normalizes consistently and an unmatched phrase remains a no-selection result', () => {
  const punctuation = planFor('Add chocolate-chips', [
    { requestIndex: 0, requestedText: 'chocolate-chips', itemId: 24, matchKind: 'semantic' },
  ]);
  assert.equal(punctuation.operations[0]?.matchKind, 'exact');

  const unmatched = planFor('Add dragon fruit', [], [
    { requestIndex: 0, requestedText: 'dragon fruit' },
  ]);
  assert.deepEqual(unmatched, {
    operations: [],
    unmatched: [{ requestIndex: 0, requestedText: 'dragon fruit' }],
  });
});

test('zero, negative, decimal, oversized, and ambiguous quantity phrases cannot select an item', () => {
  for (const requestText of [
    'Add 0 eggs', 'Add -2 eggs', 'Add 2.5 eggs', 'Add two point five eggs',
    'Add 100 eggs', 'Add one hundred eggs', 'Add two or three eggs', 'Add half dozen eggs',
  ]) {
    const phrase = buildShoppingListReaddMatchContext(requestText, candidates).phrases[0];
    assert.equal(phrase?.quantity.state, 'invalid');
    assert.throws(
      () => planFor(requestText, [{ requestIndex: 0, requestedText: phrase?.text, itemId: 22, matchKind: 'exact' }]),
      ShoppingListReaddContractValidationError,
    );
  }
});

test('duplicate targets retain one deterministic operation and report later phrases as unmatched', () => {
  const plan = planFor('Add coffee and 2 coffees', [
    { requestIndex: 0, requestedText: 'coffee', itemId: 14, matchKind: 'semantic' },
    { requestIndex: 1, requestedText: '2 coffees', itemId: 14, quantity: 2, matchKind: 'semantic' },
  ]);
  assert.deepEqual(plan.operations, [
    { requestIndex: 1, requestedText: '2 coffees', itemId: 14, quantity: 2, matchKind: 'semantic' },
  ]);
  assert.deepEqual(plan.unmatched, [{ requestIndex: 0, requestedText: 'coffee' }]);
});

test('every phrase must resolve once and a duplicate normalized candidate name is not automatically selected', () => {
  assert.throws(
    () => planFor('Add eggs and coffee', [{ requestIndex: 0, requestedText: 'eggs', itemId: 22, matchKind: 'exact' }]),
    ShoppingListReaddContractValidationError,
  );

  const duplicatedCandidates = [...candidates, { itemId: 99, itemVersion: 1, name: 'Eggs', purchased: true, quantity: 1 }];
  const context = buildShoppingListReaddMatchContext('Add eggs', duplicatedCandidates);
  assert.deepEqual(context.duplicateNormalizedNames.get('eggs'), [22, 99]);
  assert.throws(
    () => validateShoppingListReaddMatchPlanForRequest({
      operations: [{ requestIndex: 0, requestedText: 'eggs', itemId: 22, matchKind: 'exact' }],
      unmatched: [],
    }, context),
    ShoppingListReaddContractValidationError,
  );
});
