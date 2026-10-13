import { TabBar } from "@/components/tab-bar";

/**
 * A tab that exists in the nav but not yet in the database.
 *
 * The four tabs are the app's whole shape, so hiding the unfinished ones would
 * make the finished one look like the whole app and the nav would move under
 * people as phases land. This says plainly what is coming instead.
 */
export function NotBuiltYet({ title, blurb }: { title: string; blurb: string }) {
  return (
    <>
      <header className="flex-none px-4 pt-5 pb-1">
        <h1 className="text-[26px] font-semibold">{title}</h1>
      </header>
      <main className="flex min-h-0 flex-1 flex-col px-4 pt-3">
        <p className="rounded-[14px] border border-line bg-surface p-4 text-[15px] text-muted">
          {blurb}
        </p>
      </main>
      <TabBar />
    </>
  );
}
