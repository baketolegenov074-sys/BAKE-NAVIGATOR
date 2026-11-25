import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

function allowedApiKeys(): string[] {
  const values: string[] = [];
  const legacy = Deno.env.get("SUPABASE_ANON_KEY");
  if (legacy) values.push(legacy);
  const publishable = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (publishable) {
    try {
      for (const value of Object.values(JSON.parse(publishable))) {
        if (typeof value === "string") values.push(value);
      }
    } catch { /* optional environment value */ }
  }
  return values;
}
function cleanText(value: unknown, limit: number): string {
  if (typeof value !== "string") return "";
  return value.replace(/https?:\/\/[^\s]+/g, "[url]")
    .replace(/-?\d{1,2}\.\d{4,}\s*[,;]\s*-?\d{1,3}\.\d{4,}/g, "[coordinates]")
    .replace(/\n{3,}/g, "\n\n").trim().slice(0, limit);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const apiKey = req.headers.get("apikey") ?? "";
  if (!apiKey || !allowedApiKeys().includes(apiKey)) return json({ error: "unauthorized_client" }, 401);

  const githubToken = Deno.env.get("GITHUB_TOKEN");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!githubToken || !supabaseUrl || !serviceKey) return json({ error: "server_secrets_not_configured" }, 503);

  let id = "";
  try {
    const body = await req.json();
    id = typeof body?.id === "string" ? body.id.trim() : "";
  } catch { return json({ error: "invalid_json" }, 400); }
  if (!id || id.length > 100) return json({ error: "invalid_report_id" }, 400);

  const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: report, error: readError } = await db.from("app_error_reports").select("*").eq("id", id).maybeSingle();
  if (readError) return json({ error: "database_read_failed" }, 502);
  if (!report) return json({ error: "report_not_found" }, 404);
  if (report.github_issue_number) return json({ ok: true, state: "already_published", issue_url: report.github_issue_url });

  const category = ["flutter", "platform", "gps", "gps_stream"].includes(report.category) ? report.category : "other";
  const message = cleanText(report.message, 1800) || "No error message";
  const stack = cleanText(report.stack_trace, 7000);
  const details = report.details && typeof report.details === "object" && !Array.isArray(report.details)
    ? Object.fromEntries(Object.entries(report.details).filter(([key, value]) =>
        !/(lat|lon|coord|address|route|query|destination)/i.test(key) &&
        (typeof value === "string" || typeof value === "number" || typeof value === "boolean")))
    : {};

  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { data: recent, error: rateError } = await db.from("app_error_reports").select("id")
    .gte("created_at", hourAgo).not("github_issue_number", "is", null).limit(12);
  if (rateError) return json({ error: "rate_check_failed" }, 502);
  if ((recent?.length ?? 0) >= 12) return json({ error: "hourly_issue_limit" }, 429);

  await db.from("app_error_reports").update({ github_sync_started_at: null }).eq("id", id)
    .is("github_issue_number", null)
    .lt("github_sync_started_at", new Date(Date.now() - 10 * 60 * 1000).toISOString());
  const { data: claimed, error: claimError } = await db.from("app_error_reports")
    .update({ github_sync_started_at: new Date().toISOString(), github_sync_error: null })
    .eq("id", id).is("github_issue_number", null).is("github_sync_started_at", null).select("id");
  if (claimError) return json({ error: "claim_failed" }, 502);
  if (!claimed?.length) {
    const { data: latest } = await db.from("app_error_reports").select("github_issue_number, github_issue_url").eq("id", id).maybeSingle();
    if (latest?.github_issue_number) return json({ ok: true, state: "already_published", issue_url: latest.github_issue_url });
    return json({ ok: true, state: "already_processing" });
  }

  const repo = "baketolegenov074-sys/BAKE-NAVIGATOR";
  const marker = "BAKE-DIAG-ID:" + id;
  const title = "[BAKE][" + category + "] " + message.replace(/\s+/g, " ").slice(0, 150);
  const body = [
    "## Автоматический отчёт BAKE Navigator", "",
    "- Report ID: `" + id + "`",
    "- Created (UTC): " + (report.created_at ?? "unknown"),
    "- App version: " + (cleanText(report.app_version, 80) || "unknown"),
    "- Platform: " + (cleanText(report.platform, 40) || "unknown"),
    "- Category: " + category, "", "## Сообщение", message, "",
    "## Технические данные", "```json\n" + JSON.stringify(details, null, 2).slice(0, 6000) + "\n```",
    ...(stack ? ["", "## Stack trace", "```text\n" + stack + "\n```"] : []),
    "", "<!-- " + marker + " -->", "",
    "_Автоматический отчёт. Координаты и адреса маскируются перед публикацией._",
  ].join("\n");

  try {
    const search = new URL("https://api.github.com/search/issues");
    search.searchParams.set("q", "repo:" + repo + ' "' + marker + '"');
    search.searchParams.set("per_page", "1");
    const headers = {
      Authorization: "Bearer " + githubToken,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    };
    const searchResponse = await fetch(search, { headers });
    if (!searchResponse.ok) throw new Error("github_search_" + searchResponse.status);
    const searchData = await searchResponse.json();
    let issue = searchData.items?.[0];
    if (!issue) {
      const created = await fetch("https://api.github.com/repos/" + repo + "/issues", {
        method: "POST",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({ title, body }),
      });
      if (!created.ok) throw new Error("github_create_" + created.status);
      issue = await created.json();
    }
    const { error: saveError } = await db.from("app_error_reports").update({
      github_issue_number: issue.number, github_issue_url: issue.html_url,
      github_synced_at: new Date().toISOString(), github_sync_started_at: null, github_sync_error: null,
    }).eq("id", id);
    if (saveError) throw new Error("database_save_failed");
    return json({ ok: true, state: "published", issue_url: issue.html_url });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "unknown_error";
    await db.from("app_error_reports").update({
      github_sync_started_at: null, github_sync_error: reason.slice(0, 300),
    }).eq("id", id);
    return json({ error: "github_publish_failed", reason }, 502);
  }
});
