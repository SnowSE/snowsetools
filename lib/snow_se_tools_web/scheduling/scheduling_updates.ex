defmodule SnowSeToolsWeb.Scheduling.SchedulingUpdates do
  @moduledoc """
  The Updates tab of the scheduling page: what is new, with a picture and a
  short how-to for each feature. Lives inside the scheduling page, so only
  people with scheduling access (view or edit) can open it.

  Each feature has an anchor, so a message to users can link straight to it:
  `/scheduling?mode=updates#conflict-badges`.

  Screenshots are taken from made-up data (the repository is public): see
  `test/snow_se_tools_web/scheduling_updates_snapshot_test.exs` and
  `scheduling_update_screenshots.sh`, which regenerate them.

  Newest release first. To announce something new, add a release to the top
  of `releases/0`.
  """
  use SnowSeToolsWeb, :html

  @images "/images/updates/scheduling"

  # The screenshots are taken at twice the pixels; each is shown at the size
  # it was on screen, read from its PNG header when this module compiles.
  @image_dir Path.expand("../../../priv/static/images/updates/scheduling", __DIR__)

  @image_sizes (for path <- Path.wildcard(Path.join(@image_dir, "*.png")), into: %{} do
                  <<_signature::binary-size(16), width::32, height::32, _rest::binary>> =
                    File.read!(path)

                  {Path.basename(path), {div(width, 2), div(height, 2)}}
                end)

  for path <- Path.wildcard(Path.join(@image_dir, "*.png")), do: @external_resource(path)

  def releases do
    [
      %{
        id: "2026-11",
        date: "November 2026",
        title: "Reviewing a program's conflicts",
        summary:
          "Check every semester of a program for conflicts in one click, see at a glance which schedules have problems and what they are, and stop being reassured by online sections when the in-person schedule doesn't work.",
        features: [
          %{
            id: "review-program-conflicts",
            title: "Review a program's conflicts in one click",
            images: [
              %{
                file: "programs-review.png",
                alt:
                  "The Academic Programs tab with a program selected and a red Review schedule conflicts button"
              },
              %{
                file: "programs-no-conflicts.png",
                alt: "A program with a green, disabled No conflicts for this semester button"
              }
            ],
            what: [
              "The Academic Programs tab now tells you whether a program has any conflicts in the term you're looking at, and opens all of its semesters on the schedule for you.",
              "If none of the program's semesters has a conflict, the button turns green and reads \"No conflicts for this semester\". It stays as the red review button while the term is still being checked, so it never says \"no conflicts\" before it knows."
            ],
            how: [
              "Pick the term at the top of the Schedule Viewer.",
              "Open the Academic Programs tab and select a program.",
              "Click Review schedule conflicts. Every semester of the program opens as a card in the Schedule Viewer, in order."
            ]
          },
          %{
            id: "keep-your-layout",
            title: "Your unsaved layout is never thrown away",
            images: [
              %{
                file: "program-choice.png",
                alt:
                  "A dialog asking whether to add the program's semesters to the current layout or replace it"
              }
            ],
            what: [
              "If you already have schedules open that you haven't saved as a layout, reviewing a program asks first instead of clearing them."
            ],
            how: [
              "Add to layout keeps what you have and puts the program's semesters after it, skipping any that are already open.",
              "Replace layout swaps your cards for the program's semesters.",
              "Cancel (or Esc) leaves everything exactly as it was."
            ]
          },
          %{
            id: "conflict-badges",
            title: "Every schedule says whether it has conflicts",
            images: [
              %{
                file: "card-conflict-tooltip.png",
                alt:
                  "A program semester card with a hazard sign whose tooltip lists two classes meeting at the same time"
              },
              %{
                file: "card-no-conflicts.png",
                alt: "A schedule card with a green check and a No conflicts tooltip"
              }
            ],
            what: [
              "Each card on the Schedule Viewer — program semesters, professors and rooms — shows a green check when it has no conflicts and a hazard sign when it does.",
              "Hover over (or tab to) the sign to see what is wrong: a room or professor booked twice, or two of a semester's classes meeting at the same time, with the classes and the days and times they overlap. When an online section would get a student out of the clash, it is named too.",
              "Conflicts you have acknowledged in the Schedule Conflicts panel don't count. Conflicts from the change group you have selected do."
            ],
            how: [
              "Open any schedule in the Schedule Viewer.",
              "Hover over the check or hazard sign next to its name."
            ]
          },
          %{
            id: "conflicts-first",
            title: "The options with conflicts come first",
            images: [
              %{
                file: "options-pager.png",
                alt: "A program semester card showing Option 1 of 2, 1 with conflicts"
              }
            ],
            what: [
              "A program semester can usually be taken several ways — different sections of each class. Those options are now ordered with every option that has a conflict first, so you see the problems on the first pages instead of hunting for them.",
              "The card says how many of its options have conflicts. Page past them with the arrows to see the options that work."
            ],
            how: [
              "Open a program semester (or review a whole program).",
              "Read the count next to the arrows, then use the arrows to step through the options."
            ]
          },
          %{
            id: "in-person-options",
            title: "Options are built from in-person classes",
            images: [
              %{
                file: "lab-pairs.png",
                alt:
                  "Option 2 of a program semester: CS 1400 section 001 on Monday, Wednesday and Friday at 9:30, with its own lab, CS 1405 section 001, on Tuesday at 9:30"
              }
            ],
            what: [
              "To answer \"can we offer this semester face to face?\", options now use only in-person sections (hybrid counts as in person). Online sections can no longer hide an in-person clash. Instead, a clash tells you which online section would avoid it.",
              "Options use one campus — whichever teaches most of the semester's classes in person, Ephraim for our programs — so a Richfield section won't stand in for an Ephraim student's. A class taught in person only on another campus still uses those sections, and a class that is only offered online still appears, in the card's Online list.",
              "Labs stay with their lecture: a lab whose section number matches a lecture section (001 and 001) goes only with that lecture, and an in-person lecture goes with an in-person lab. Labs are matched by course number: the lab is the lecture's number plus 5 (CS 1410 and CS 1415)."
            ],
            how: [
              "Nothing to do. Every program semester card works this way."
            ]
          },
          %{
            id: "no-blank-semesters",
            title: "No more blank semesters",
            images: [
              %{
                file: "not-offered.png",
                alt:
                  "A program semester card whose hazard tooltip says a course isn't offered this term"
              }
            ],
            what: [
              "A semester used to show up empty when its classes couldn't all fit together. Now it shows the combinations with the fewest overlaps, with the clashing classes outlined in red and the hazard sign saying which ones meet at once.",
              "If a required course isn't offered at all in the term you're viewing — a fall course while looking at spring, say — the card says so by name."
            ],
            how: [
              "Look for the hazard sign on a program semester card and hover over it."
            ]
          },
          %{
            id: "online-list-open",
            title: "Online classes are listed openly",
            images: [
              %{
                file: "online-box.png",
                alt: "The Online list under a schedule, open and showing an online class"
              }
            ],
            what: [
              "The Online list under each schedule now starts open, so online classes can't be missed. It also counts classes now, where it used to say \"credits\"."
            ],
            how: [
              "Click the Online heading to fold the list away when you don't need it."
            ]
          },
          %{
            id: "same-name-instructors",
            title: "Instructors who share a name are kept apart",
            images: [
              %{
                file: "same-name-search.png",
                alt:
                  "Schedule search listing two instructors with the same name, each followed by their email address"
              }
            ],
            what: [
              "Two instructors with the same name used to be merged into one schedule holding both of their classes. Each now has their own schedule.",
              "Where two people share a name, their email address is shown after it — in search, on the card, and in the professor list when you edit a course. Everyone else still appears by name alone."
            ],
            how: [
              "Search for the name and pick the right person by email.",
              "Moving a class onto one of their cards, or choosing them by email when editing a course, assigns it to exactly that person."
            ]
          },
          %{
            id: "reconnect",
            title: "Your schedules come back after a dropped connection",
            images: [],
            what: [
              "If your connection dropped for a moment, the cards you had open could disappear. They now come back by themselves when the connection does."
            ],
            how: []
          }
        ]
      }
    ]
  end

  def render(assigns) do
    assigns = assign(assigns, :releases, releases())

    ~H"""
    <div id="scheduling-updates" class="h-full overflow-y-auto">
      <div class="mx-auto w-full max-w-5xl px-4 py-6 sm:px-6">
        <header class="mb-6">
          <h1 class="text-xl font-semibold text-slate-100">What's new in scheduling</h1>
          <p class="mt-1 text-sm text-slate-400">
            New features in the scheduling tools, newest first, with how to use them.
          </p>
        </header>

        <section
          :for={release <- @releases}
          id={"update-#{release.id}"}
          class="mb-10"
        >
          <div class="mb-4 border-b border-slate-800 pb-3">
            <p class="text-xs font-medium uppercase tracking-wide text-indigo-300">{release.date}</p>
            <h2 class="mt-1 text-lg font-semibold text-slate-100">{release.title}</h2>
            <p class="mt-1 max-w-3xl text-sm text-slate-400">{release.summary}</p>

            <nav aria-label={"In #{release.title}"} class="mt-3">
              <ul class="flex flex-wrap gap-1.5">
                <li :for={feature <- release.features}>
                  <a
                    href={"##{feature.id}"}
                    class="inline-block rounded-md bg-slate-800/70 px-2 py-1 text-xs text-slate-300 transition hover:bg-slate-700 hover:text-slate-100"
                  >
                    {feature.title}
                  </a>
                </li>
              </ul>
            </nav>
          </div>

          <article
            :for={feature <- release.features}
            id={feature.id}
            class="mb-6 scroll-mt-4 rounded-xl border border-slate-800 bg-slate-950/45 p-4 sm:p-5"
          >
            <h3 class="text-base font-semibold text-slate-100">
              <a href={"##{feature.id}"} class="hover:text-indigo-200">{feature.title}</a>
            </h3>

            <div :for={paragraph <- feature.what} class="mt-2 max-w-3xl text-sm text-slate-300">
              {paragraph}
            </div>

            <div :if={feature.how != []} class="mt-4">
              <h4 class="text-xs font-medium uppercase tracking-wide text-slate-500">
                How to use it
              </h4>
              <ol class="mt-1.5 max-w-3xl list-decimal space-y-1 pl-5 text-sm text-slate-300">
                <li :for={step <- feature.how}>{step}</li>
              </ol>
            </div>

            <%!-- At the size it was on screen: readable, never stretched. --%>
            <div :if={feature.images != []} class="mt-4 flex flex-col items-start gap-3">
              <a
                :for={image <- feature.images}
                href={image_path(image)}
                target="_blank"
                rel="noopener"
                class="block max-w-full overflow-hidden rounded-lg border border-slate-800 bg-slate-950 transition hover:border-slate-600"
                title="Open full size"
              >
                <img
                  src={image_path(image)}
                  width={image_width(image)}
                  height={image_height(image)}
                  alt={image.alt}
                  loading="lazy"
                  class="block h-auto max-w-full"
                />
              </a>
            </div>
          </article>
        </section>
      </div>
    </div>
    """
  end

  def image_path(%{file: file}), do: "#{@images}/#{file}"

  defp image_width(%{file: file}), do: @image_sizes |> Map.get(file, {nil, nil}) |> elem(0)
  defp image_height(%{file: file}), do: @image_sizes |> Map.get(file, {nil, nil}) |> elem(1)
end
