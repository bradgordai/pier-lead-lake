# Nailed It AI, workspace coding standards

## Frontend patterns
- React with TanStack Router and TanStack Query
- shadcn/ui component library only, no other UI kits
- Tailwind CSS for styling, use tokens not raw hex where possible
- No inline styles, no CSS modules
- All Supabase queries live in src/lib/queries/*.ts
- Every query is typed with QueryData<typeof query>
- Every list query uses .range() and returns a total count
- Every mutation uses .throwOnError() and TanStack Query invalidation

## Supabase patterns
- Server-side code hits port 6543 (Supavisor pooler), never 5432
- Every FK column has a btree index (verified in migration audits)
- Every RLS policy wraps auth.uid() as (SELECT auth.uid())
- Never use user_metadata in RLS policies
- Never expose SECURITY DEFINER views through the PostgREST API
- Every Realtime subscription cleans up on component unmount
- Never issue N+1 queries client-side, always use PostgREST nested selects

## Auth patterns
- Supabase Auth with email/password and Google OAuth
- profiles table populated by handle_new_user() trigger, with SECURITY DEFINER
- Team-scoped RLS pattern: team_id column on every row, membership check via fn_user_teams()

## Naming
- snake_case in database, camelCase in TypeScript
- Query functions named after the operation: getCompanies, updateContact, insertOutreach
- Component names match their route or feature: CompaniesList, CompanyDetail

## Testing rules
- No feature is done until: the code passes lint, the RLS policies are audited via pg_policies, and the query returns expected data at both anon and service-role scope.
