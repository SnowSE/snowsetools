
above all else, ask the user clarifying quesitons whenever it is necessary. before making assumptions about things not inlcuded in the instructions, verify the user is OK with that direction.


- **Use named parameters for functions with multiple parameters**
      defp fetch_paginated_items(url: url, current_page: current_page, total_pages: total_pages) do
        # ... function body
      end


## LiveComponent State and PubSub

LiveComponents may keep local UI state in `socket.assigns` (e.g. `syncing`, `progress`, `error`). Use `assign_new/3` to initialize component-local state once without resetting it on every parent update.

```elixir
socket
|> assign_new(:syncing, fn -> false end)
|> assign_new(:progress, fn -> 0 end)
```

LiveComponents do **not** run in their own process. They share the parent LiveView process and mailbox. As a result:

* Do not subscribe to PubSub from a component, make a helper function in the component module and call the helper in the liveview
* Do not use components as the primary receiver of external process messages, have the message go to the parent liveview and pass the messages to the cild component with send_update
* Subscribe in the LiveView and handle PubSub messages in the LiveView's `handle_info/2`.

Preferred pattern:

```elixir
# LiveView
def mount(_, _, socket) do
  if connected?(socket) do
    MyPubSub.subscribe()
  end

  {:ok, socket}
end

def handle_info({:progress, value}, socket) do
  send_update(MyComponent,
    id: "sync-status",
    progress: value
  )

  {:noreply, socket}
end
```

```elixir
# Component
def update(%{progress: progress}, socket) do
  {:ok, assign(socket, progress: progress)}
end
```

Rule of thumb:

* LiveComponent = local UI state and rendering.
* LiveView = PubSub subscriptions, process messages, external events, and coordination between components.


## never silently fail

never ignore reasons without logging them (ideally handle them)
```elixir
{:error, _reason} ->
  {:noreply, socket}
```
do this instead
```elixir
{:error, reason} ->
  Logger.error("error in <this scenario> #{io.inspect(reason)}")
  {:noreply, socket}
```

## general instructions

do not include useless comments, if the code is not easy to read, use better naming conventions and single-level of abstraction functions.

never silently ignore errors. make sure that errors properly get displayed to the user via either message passing or pubsub. 

avoid empty catch-all clauses that hide errors

## Database

Phoenix connects to Postgres via `Ecto.Repo` (no Ecto schemas). All queries use `DbHelpers.run_sql/2,3` with named parameters (`$(param_name)`), which are converted to positional Postgrex params at runtime. Query results are optionally validated against a Zoi schema.

• Use DbHelpers.run_sql/3 with explicit sql, params, and a Zoi schema:
```elixir
  schema =
    Zoi.object(%{
      id: Zoi.uuid(),
      email: Zoi.string()
    })

  sql = """
  SELECT id, email
  FROM users
  WHERE id = $(user_id)
  """

  params = %{"user_id" => Uuid.to_binary(user_id)}

  case DbHelpers.run_sql(sql, params, schema) do
    [{user}] -> {:ok, user}
    [] -> {:error, :not_found}
    {:error, reason} -> {:error, reason}
  end
```

Postgrex UUID params must be 16-byte binaries; convert UUID strings with SnowSeTools.Data.Uuid.to_binary/1
before passing them to DbHelpers.run_sql/2,3.

```elixir
alias SnowSeTools.Data.{DbHelpers, Uuid}

sql = """
SELECT id, name
FROM academic_programs
WHERE id = $(id)
"""

params = %{"id" => Uuid.to_binary(program_id)}

DbHelpers.run_sql(sql, params)
```

UI updates should not talk to SQL directly. Flow should be:

- LiveView handle_event/3 calls a domain manager with GenServer.cast/2
- Domain manager does DB work
- Domain manager sends results back with send(pid, ...) or PubSub
- LiveView handles handle_info/2 and updates assigns or flashes

LiveView

```elixir
  def handle_event("save", %{"group" => attrs}, socket) do
    AdminDomainManager.create_group(pid: self(), group_params: attrs)
    {:noreply, socket}
  end

  def handle_info({:admin_action_result, {:error, reason}}, socket) do
    {:noreply, put_flash(socket, :error, inspect(reason))}
  end
```

  Rule of thumb:

  - DB access in data modules
  - coordination in domain managers
  - UI feedback in LiveView via handle_info/2, put_flash/3, assign/3, or send_update/2
<!-- 
## LiveComponent Events

When adding `phx-click`, `phx-change`, `phx-submit`, or any other LiveView event binding inside a LiveComponent, always
set `phx-target={@myself}` unless the event is intentionally handled by the parent LiveView.

```elixir
<button
  type="button"
  phx-click="close"
  phx-target={@myself}
>
  <.icon name="hero-x-mark" />
</button>
```

LiveComponent events without phx-target={@myself} are sent to the parent LiveView, not the component. This often causes
missing handler bugs when the component defines handle_event/3 but the event is never delivered to it. -->

## Stateful Widgets via Hooked Function Components

State lives as a struct in `socket.assigns`. Hooks intercept the parent LiveView's lifecycle. Rendering is a pure function component. Event hooks should be defined and implemented in the same file that manages the UI for that data.

```elixir
defmodule ChatWidget do
  defstruct [:key, :topic]

  def assign_component(socket, key, opts \\ []) do
    socket
    |> assign(key, %ChatWidget{key: key, topic: opts[:topic] || "chat:global"})
    |> maybe_attach_hooks()
  end

  defp maybe_attach_hooks(socket) do
    if first_instance?(socket) do
      socket
      |> LiveView.attach_hook("chat:event",  :handle_event,  &hooked_event/3)
      |> LiveView.attach_hook("chat:info",   :handle_info,   &hooked_info/2)
      |> LiveView.attach_hook("chat:params", :handle_params, &hooked_params/3)
    else
      socket
    end
  end

  defp hooked_event("chat-widget:send", %{"chat-widget-key" => k, "message" => msg}, socket) do
    state = socket.assigns[String.to_existing_atom(k)]
    ChatContext.send_message(msg, state.topic)
    {:halt, socket}
  end
  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp hooked_info({:new_message, msg}, socket),
    do: {:cont, update_matching_widgets(socket, msg)}
  defp hooked_info(_msg, socket), do: {:cont, socket}

  def render(assigns) do
    ~H"""
    <form phx-submit="chat-widget:send">
      <input type="hidden" name="chat-widget-key" value={@state.key} />
      <input type="text" name="message" />
    </form>
    """
  end
end
```

Parent usage:

```elixir
def mount(_params, _session, socket),
  do: {:ok, socket |> ChatWidget.assign_component(:chat)}

def render(assigns),
  do: ~H"<ChatWidget.render state={@chat} message_stream={@streams.chat} />"
```

Hooks attach once regardless of instance count. `:halt` stops propagation; `:cont` passes through. Always use `:cont` for `handle_info` and `handle_params`. Pass streams as a separate template attribute rather than embedding in the struct.



When html conponents are rendered in a list, we still want the componnet to own its data logic, identify individual instances with unique ID's

```elixir
def assign_component(socket, id) do
  socket
  |> assign(:"item_#{id}", %ItemWidget{key: :"item_#{id}", id: id})
  |> maybe_attach_hooks()
end

defp hooked_event("item-widget:toggle", %{"item-id" => id}, socket) do
  key = :"item_#{id}"
  {:halt, update(socket, key, &%{&1 | expanded: !&1.expanded})}
end

defp hooked_event(_event, _params, socket), do: {:cont, socket}
```

The ID travels with every event as a `phx-value-*` or hidden field:

```elixir
def render(assigns) do
  ~H"""
  <div>
    <button phx-click="item-widget:toggle" phx-value-item-id={@state.id}>
      Toggle
    </button>
    <div :if={@state.expanded}>...</div>
  </div>
  """
end
```

Mount by mapping over your list:

```elixir
def mount(_params, _session, socket) do
  socket = Enum.reduce(items, socket, fn item, acc ->
    ItemWidget.assign_component(acc, item.id)
  end)
  {:ok, socket}
end

def render(assigns) do
  ~H"""
  <div :for={{_key, state} <- Enum.filter(@assigns, &match?({_, %ItemWidget{}}, &1))}>
    <ItemWidget.render state={state} />
  </div>
  """
end
```

The main constraint: all list items share one set of hooks, so event names must be namespaced and every handler must identify the target instance via the ID rather than assuming a single widget exists.

---

## Dev Environment

`docker compose up` starts two containers:

1. **db** — Postgres 17; `schema.sql` is mounted and run on first start
   - you can run sql with `docker exec simplesyllabusreporter-db-1 sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB -c "\dt"'`
2. **app** — Elixir/Phoenix; source is bind-mounted so live reload works

## Production Deployment

Production runs as a docker compose stack (`docker-compose.prod.yml`) behind a
Cloudflare tunnel — it replaces the old k8s/ArgoCD deployment.

```bash
cp prod.env.example prod.env   # then fill in every REPLACE_ME
./prod.sh up -d --build        # build the release image and start the stack
./prod.sh logs -f app
```

Always go through `./prod.sh` rather than `docker compose` directly — it passes
both `-f docker-compose.prod.yml` and `--env-file prod.env`, and the `${VAR}`
substitutions in the compose file fail without the latter.

Three containers:

1. **db** — Postgres 18, data in the `postgres_data` named volume; `schema.sql`
   is mounted into `/docker-entrypoint-initdb.d/` and runs only on first start
   (i.e. when the volume is empty). There are no Ecto migrations; schema
   changes are applied by editing `schema.sql` **and** running the equivalent
   SQL against the live database by hand.
2. **app** — the prod `Dockerfile` release image. `DATABASE_URL` is assembled by
   compose from the `POSTGRES_*` values, so it is not set in `prod.env`.
3. **cloudflared** — a token-based tunnel; the public hostname → `http://app:4000`
   mapping lives in the Cloudflare Zero Trust dashboard, not in this repo. No
   host ports are published, so the app is reachable only through the tunnel.

`PHX_HOST`, `OIDC_REDIRECT_URI`, and the tunnel's public hostname must all agree,
or OIDC login breaks.

## Getting feedback

you can read current logs with `docker logs simplesyllabusreporter-app-1` be sure to use bash to filter for only the logs you care about.

when checking if changes compile use `./precommit-check.sh` on the terminal (not in container)

when running tests they will not work in the docker environment. run `./precommit-check.sh` or `./precommit-check.sh test <file>` on the host to run tests.

`./precommit-check.sh` will also format the documents


## Data Flows

The UI layer (in the snow_se_tools_web folder) should only communicate with the domain manager agents to get data. Never let a liveview talk directly to the database or service layers.

All UI communication with domain managers should be asyncronous through Genserver.Cast data will flow back through pubsub or response messages.

Use the asyncronous model to leverage Phoenix Streams when rendering and updating large amounts of data.









--- Phoenix guidelines below ---

## Project guidelines

- Use `./precommit-check.sh` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- organize files and folders by feature name, not file type. for example liveviews about syllabus go in `snow_se_tools_web/syllabus/syllabus_live.ex` not in a `live` folder

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** write raw css, prefer to inline tailwindcss classes
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- focus on heiraricy if in formation, make the most important information the first thing the user sees
    - avoid useless information on the page
- keep feedback on interactions spacially close to the element that triggered the interaction. Error messages and loading indicators should be close to the user.
- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions
- ensure that the foreground color and backround color match (do not put rose text on slate background)
  - usually this means making a semi-transparent backround color for the element


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items
  along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- Edit mode --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide an unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors, 1) colocated js hooks for "inline" scripts defined inside HEEx,
and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

#### Inline colocated js hooks

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView.
Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`)
when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

#### External phx-hook

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the
LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events between client and server

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle.
**Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")
