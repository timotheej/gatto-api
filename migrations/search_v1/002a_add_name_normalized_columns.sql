-- Migration 002a: Add normalized name columns (PART 1 - Fast)
-- Date: 2025-12-11
-- Description: Create normalize function and computed columns
-- Duration: ~1-2 seconds

-- ============================================================================
-- HELPER FUNCTION: Normalize text for search
-- ============================================================================

CREATE OR REPLACE FUNCTION normalize_for_search(input_text TEXT)
RETURNS TEXT AS $$
  SELECT lower(
    unaccent(
      translate(
        COALESCE(input_text, ''),
        chr(8217) || chr(8216),  -- U+2019 ' and U+2018 ' (smart quotes)
        chr(39) || chr(39)        -- U+0027 ' (standard apostrophe)
      )
    )
  )
$$ LANGUAGE SQL IMMUTABLE;

-- Test: SELECT normalize_for_search('Café de l''Opéra');
-- Expected: "cafe de l'opera"


-- ============================================================================
-- ADD NORMALIZED COLUMNS (Generated/Computed columns)
-- ============================================================================

ALTER TABLE poi
ADD COLUMN IF NOT EXISTS name_normalized TEXT
GENERATED ALWAYS AS (normalize_for_search(name)) STORED;

ALTER TABLE poi
ADD COLUMN IF NOT EXISTS name_fr_normalized TEXT
GENERATED ALWAYS AS (normalize_for_search(name_fr)) STORED;

ALTER TABLE poi
ADD COLUMN IF NOT EXISTS name_en_normalized TEXT
GENERATED ALWAYS AS (normalize_for_search(name_en)) STORED;


-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Check columns were created:
-- SELECT column_name, data_type, is_generated
-- FROM information_schema.columns
-- WHERE table_name = 'poi'
--   AND column_name LIKE '%normalized%';

-- Test normalization:
-- SELECT name, name_normalized FROM poi LIMIT 5;
