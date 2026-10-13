import "server-only";

import { createClient } from "./supabase/server";
import type { Database } from "./database.types";

export type Invoice = Database["public"]["Tables"]["invoice"]["Row"];
export type LedgerEntry = Database["public"]["Tables"]["ledger_entry"]["Row"];
export type EntryKind = Database["public"]["Enums"]["ledger_entry_kind"];

/** A proposed line, before anybody owes it. The shape `month_charges` returns. */
export type Charge =
  Database["public"]["Functions"]["month_charges"]["Returns"][number];

/**
 * Reads for the Bills tab.
 *
 * Every figure here comes from the ledger or from month_charges(), and nothing
 * in this file adds up money the database has not already added up. SPEC.md
 * 4.6 is blunt about it -- "Never compute balances anywhere else" -- and the
 * reason is that a second opinion about a balance is indistinguishable from a
 * bug until someone is overcharged.
 */

/**
 * What a member owes for a month that has not been closed yet.
 *
 * The same function the close uses, so the review step cannot disagree with
 * the invoice it is reviewing. Returns [] when the month is empty.
 */
export async function getMonthCharges(
  aircraftId: string,
  memberId: string,
  month: string,
): Promise<Charge[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("month_charges", {
    p_aircraft_id: aircraftId,
    p_member_id: memberId,
    p_month: month,
  });
  return data ?? [];
}

/** An invoice with what it adds up to, which only the database may say. */
export type InvoiceWithTotal = { invoice: Invoice; total: number };

/**
 * The invoices a member can look back at, newest first.
 *
 * Drafts are excluded: a draft is a proposal an admin has not sent, and it
 * would read as a bill. Void ones stay, because an invoice that was issued and
 * then cancelled is part of the story of the account.
 */
export async function getInvoiceHistory(
  memberId: string,
): Promise<InvoiceWithTotal[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("invoice")
    .select("*")
    .eq("member_id", memberId)
    .neq("status", "draft")
    .order("period_month", { ascending: false });

  return Promise.all(
    (data ?? []).map(async (invoice) => {
      const { data: total } = await supabase.rpc("invoice_total", {
        p_invoice_id: invoice.id,
      });
      return { invoice, total: Number(total ?? 0) };
    }),
  );
}

/**
 * Payments, payouts and adjustments -- the entries that are not lines of an
 * invoice. Shown beside the invoices so "where did $800 go" has an answer
 * without opening anything.
 */
export async function getLooseEntries(memberId: string): Promise<LedgerEntry[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("ledger_entry_posted")
    .select("*")
    .eq("member_id", memberId)
    .is("invoice_id", null)
    .order("entry_date", { ascending: false })
    .limit(24);
  return (data as LedgerEntry[] | null) ?? [];
}

/** The most recent payment, for the "Last payment" line on the Bills screen. */
export async function getLastPayment(memberId: string): Promise<LedgerEntry | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("ledger_entry_posted")
    .select("*")
    .eq("member_id", memberId)
    .eq("kind", "payment")
    .order("entry_date", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data as LedgerEntry | null) ?? null;
}

export async function getInvoice(id: string): Promise<Invoice | null> {
  const supabase = await createClient();
  const { data } = await supabase.from("invoice").select("*").eq("id", id).maybeSingle();
  return data ?? null;
}

export async function getInvoiceLines(invoiceId: string): Promise<LedgerEntry[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("ledger_entry")
    .select("*")
    .eq("invoice_id", invoiceId)
    .order("kind")
    .order("description");
  return data ?? [];
}

/**
 * The hours an issued invoice was billed for.
 *
 * Counted off the flights locked to it rather than off its charge lines: the
 * lines are one per rate component and all carry the same hours, so summing
 * them would multiply the flying by six.
 */
export async function getInvoiceHours(invoiceId: string): Promise<number> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("flight")
    .select("billed_hours")
    .eq("invoice_id", invoiceId);
  return (data ?? []).reduce((total, f) => total + Number(f.billed_hours ?? 0), 0);
}

/**
 * Every active member's balance, for the admin's month-close screen.
 *
 * SPEC.md 4.6: "Only an admin sees all pilots' numbers." Nothing filters that
 * here -- `member_balance` is not security definer, so a pilot who reached this
 * would get zeroes from RLS rather than the figures.
 *
 * The role comes with it because the payment screen needs to know whether a
 * second admin exists before it decides whose name to offer.
 */
export async function getRoster(): Promise<
  {
    id: string;
    full_name: string;
    role: Database["public"]["Enums"]["member_role"];
    balance: number;
  }[]
> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("member")
    .select("id, full_name, role")
    .eq("is_active", true)
    .order("full_name");

  return Promise.all(
    (data ?? []).map(async (member) => {
      const { data: balance } = await supabase.rpc("member_balance", {
        p_member_id: member.id,
      });
      return { ...member, balance: Number(balance ?? 0) };
    }),
  );
}

/** The drafts standing for a month, with their totals, for the review step. */
export async function getDrafts(
  month: string,
): Promise<{ invoice: Invoice; member: string; total: number }[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("invoice")
    .select("*, member:member!invoice_member_id_fkey(full_name)")
    .eq("period_month", month)
    .eq("status", "draft");

  return Promise.all(
    (data ?? []).map(async (row) => {
      const { member, ...invoice } = row as Invoice & {
        member: { full_name: string } | null;
      };
      const { data: total } = await supabase.rpc("invoice_total", {
        p_invoice_id: invoice.id,
      });
      return {
        invoice,
        member: member?.full_name ?? "a former owner",
        total: Number(total ?? 0),
      };
    }),
  );
}

/** The e-Transfer details the Pay screen shows. */
export async function getPaymentDetails(): Promise<{
  recipient: string | null;
  legalName: string;
} | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("company")
    .select("legal_name, etransfer_recipient")
    .limit(1)
    .maybeSingle();
  if (!data) return null;
  return { recipient: data.etransfer_recipient, legalName: data.legal_name };
}
