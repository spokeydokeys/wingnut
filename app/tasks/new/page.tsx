import { createTask } from "@/app/tasks/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { requireMember } from "@/lib/dal";
import { getPilotChoices } from "@/lib/flights";

export const dynamic = "force-dynamic";

/**
 * A one-off: ring the hangar owner about the water leak.
 *
 * Defaults to the person typing it, because the common case is writing down
 * something you have just agreed to do. Both the assignee and the date are
 * optional -- a task nobody has picked up yet is still worth recording, and so
 * is one with no deadline.
 */
export default async function NewTask() {
  const member = await requireMember();
  const people = await getPilotChoices();

  return (
    <>
      <BackHeader href="/tasks" label="Tasks" title="New task" />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={createTask} submitLabel="Add task">
          <div>
            <label htmlFor="title" className="field-label mb-1.5 block">
              What needs doing
            </label>
            <input
              id="title"
              name="title"
              required
              placeholder="Ring the hangar owner about the leak"
              className={FIELD}
            />
          </div>

          <div>
            <label htmlFor="assignee_member_id" className="field-label mb-1.5 block">
              Whose it is
            </label>
            <select
              id="assignee_member_id"
              name="assignee_member_id"
              defaultValue={member.id}
              className={FIELD}
            >
              <option value="">Nobody yet</option>
              {people.map((person) => (
                <option key={person.id} value={person.id}>
                  {person.full_name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label htmlFor="due_date" className="field-label mb-1.5 block">
              Due (optional)
            </label>
            <input id="due_date" name="due_date" type="date" className={FIELD} />
          </div>

          <div>
            <label htmlFor="detail" className="field-label mb-1.5 block">
              Detail
            </label>
            <textarea
              id="detail"
              name="detail"
              rows={3}
              placeholder="Anything the next person would need to know"
              className={`${FIELD} h-auto py-2.5`}
            />
          </div>
        </ActionForm>
      </main>
    </>
  );
}
