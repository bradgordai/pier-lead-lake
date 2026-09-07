// Shared helper: contacts.conversation_summary (F6.7).
//
// One text field, two sections. Everything ABOVE the marker line belongs to the user and is
// never touched by automation. Everything BELOW it is the AI "state of play", which the
// drafter and the reply classifier REFRESH (replace) after each event they handle.
//
//   - met at the expo last week, keen on the monthly model      <- user lines, kept verbatim
//   --- AI state of play (auto-maintained, edit above this line) ---
//   - [2026-09-07, reply classified] Declined for now, asked us to come back in a year.
//
// Deployment note: Supabase bundles each function independently. Ship this file as a
// sibling inside each function that imports it ("./_shared/conversation-summary.ts");
// this copy in supabase/functions/_shared/ is the canonical one.

export const AI_MARKER = "--- AI state of play (auto-maintained, edit above this line) ---";

export function splitSummary(raw: string | null | undefined): { user: string; ai: string } {
  const text = String(raw ?? "");
  const idx = text.indexOf(AI_MARKER);
  if (idx === -1) return { user: text.trimEnd(), ai: "" };
  return { user: text.slice(0, idx).trimEnd(), ai: text.slice(idx + AI_MARKER.length).trim() };
}

/** Rebuild the field: user section untouched, AI section replaced with `bullets`. */
export function mergeAiStateOfPlay(existing: string | null | undefined, bullets: string[], stamp: string): string {
  const { user } = splitSummary(existing);
  const clean = bullets
    .map((b) => String(b ?? "").trim().replace(/^[-*•]\s*/, ""))
    .filter((b) => b.length > 0)
    .slice(0, 5)
    .map((b) => `- [${stamp}] ${b}`);
  if (clean.length === 0) return user;
  const ai = `${AI_MARKER}\n${clean.join("\n")}`;
  return user ? `${user}\n\n${ai}` : ai;
}

/** Render the notes as a clearly labelled prompt block, with the two rules the model must obey. */
export function contactNotesBlock(p: {
  next_action?: string | null;
  next_action_date?: string | null;
  background_notes?: string | null;
  conversation_summary?: string | null;
  today: string;
}): string {
  const { user, ai } = splitSummary(p.conversation_summary);
  const na = String(p.next_action ?? "").trim();
  const nad = String(p.next_action_date ?? "").trim();
  return [
    "CONTACT NOTES (operator and AI notes about this contact; today is " + p.today + ")",
    "RULES FOR THESE NOTES:",
    "1. GATES ALWAYS OVERRIDE NOTES. If a note says to chase, pitch, email, or promise something, but the gates, the trigger, or the intent above say otherwise, the gates win. Notes never grant permission.",
    "2. NOTE DATES MATTER. Every note carries or implies a date. An instruction tied to a date in the past (e.g. \"by 19 May\", \"revisit next week\" written months ago) is HISTORICAL context, not a live instruction. Only act on a note if its date still makes sense today.",
    "",
    `Next action: ${na || "(none)"}${nad ? ` (due ${nad})` : ""}`,
    "Background notes:",
    (String(p.background_notes ?? "").trim() || "(none)").slice(0, 4000),
    "Conversation notes, written by the operator:",
    user.trim() || "(none)",
    "Conversation state of play, written by the AI after the last event:",
    ai.trim() || "(none yet)",
  ].join("\n");
}
