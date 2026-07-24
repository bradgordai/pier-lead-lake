-- Migration 020: JSONB type CHECK constraints on user_column_prefs
--
-- 019 created visible_columns / column_widths as NOT NULL JSONB with '[]' / '{}'
-- defaults, but nothing pinned their *shape*. JSONB accepts any valid JSON, so a
-- client writing a bare string or a number would be stored happily and only fail
-- later at read time, in the list view, when the column code tried to iterate it.
-- Pin the shape at the table so bad writes fail where they happen.

ALTER TABLE public.user_column_prefs
  ADD CONSTRAINT visible_columns_is_array
  CHECK (jsonb_typeof(visible_columns) = 'array');

ALTER TABLE public.user_column_prefs
  ADD CONSTRAINT column_widths_is_object
  CHECK (jsonb_typeof(column_widths) = 'object');
