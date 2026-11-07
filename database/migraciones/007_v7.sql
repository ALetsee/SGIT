-- v7: agrega concepto GARANTIA (permite partidas sin cargo para trabajos en garantía)
ALTER TYPE tipo_concepto ADD VALUE IF NOT EXISTS 'GARANTIA';
