BEGIN;

ALTER TABLE shopping_ai_readd_operations
  ADD COLUMN IF NOT EXISTS applied_version INTEGER;

ALTER TABLE shopping_ai_readd_operations
  DROP CONSTRAINT IF EXISTS shopping_ai_readd_operations_applied_version_valid,
  ADD CONSTRAINT shopping_ai_readd_operations_applied_version_valid
    CHECK (applied_version IS NULL OR applied_version >= 1);

ALTER TABLE shopping_ai_readd_operations
  DROP CONSTRAINT IF EXISTS shopping_ai_readd_operations_undo_facts_valid,
  ADD CONSTRAINT shopping_ai_readd_operations_undo_facts_valid
    CHECK (
      undo_status = 'not_eligible'
      OR (
        target_item_id IS NOT NULL
        AND snapshot_version IS NOT NULL
        AND prior_purchased IS NOT NULL
        AND prior_quantity IS NOT NULL
        AND applied_purchased IS NOT NULL
        AND applied_quantity IS NOT NULL
        AND applied_version IS NOT NULL
      )
    );

COMMIT;
