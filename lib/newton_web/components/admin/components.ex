defmodule NewtonWeb.Admin.Components do
  @moduledoc """
  The shared visual skeleton of the admin: the chrome that recurs across admin
  LiveViews (page and section headers, lists and rows, drawers, buttons, form
  fields, the markdown editor) lives here as slot-based function components, so
  each page composes it instead of copying markup.
  """
  use NewtonWeb, :html

  @doc """
  A right-hand slide-over drawer. The caller renders it conditionally
  (`:if={@open?}`) and passes `on_close` — a `Phoenix.LiveView.JS` command or an
  event name — which fires on the close button, Escape, and a click outside.
  """
  attr :id, :string, required: true
  attr :on_close, :any, required: true
  slot :title, required: true
  slot :inner_block, required: true

  def drawer(assigns) do
    ~H"""
    <div
      id={@id}
      phx-window-keydown={@on_close}
      phx-key="Escape"
      phx-click-away={@on_close}
      phx-mounted={
        JS.transition(
          {"transition-transform ease-out duration-200", "translate-x-full", "translate-x-0"},
          time: 200
        )
      }
      phx-remove={
        JS.transition(
          {"transition-transform ease-in duration-200", "translate-x-0", "translate-x-full"},
          time: 200
        )
      }
      class="fixed inset-y-0 right-0 z-20 flex w-80 max-w-[calc(100vw-3rem)] flex-col gap-4 overflow-y-auto border-l border-(--admin-border) bg-(--admin-sidebar) p-5 shadow-xl"
    >
      <div class="flex items-center justify-between">
        <span class="text-[0.9rem] font-semibold">{render_slot(@title)}</span>
        <button
          type="button"
          phx-click={@on_close}
          aria-label="Close"
          class="text-(--admin-text-subtle) hover:text-(--admin-text)"
        >
          <.icon name="hero-x-mark-mini" class="size-5" />
        </button>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A form field styled for the admin theme. Wraps the core `<.input>` so drawer
  fields share the post editor's surface/border/text colors in light and dark.
  """
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :name, :any, default: nil
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :options, :list, default: []
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(rows placeholder autocomplete readonly required list)

  def field(%{field: %Phoenix.HTML.FormField{}} = assigns) do
    ~H"""
    <.input
      field={@field}
      type={@type}
      label={@label}
      options={@options}
      class={field_class()}
      {@rest}
    />
    """
  end

  def field(assigns) do
    ~H"""
    <.input
      name={@name}
      value={@value}
      type={@type}
      label={@label}
      options={@options}
      errors={@errors}
      class={field_class()}
      {@rest}
    />
    """
  end

  @doc """
  The admin's token-styled button. `variant` picks the look:

    * `primary` (default) — accent fill, for the main action
    * `secondary` — bordered, for a lesser action (e.g. "Move to draft")
    * `danger` — bordered accent text, for destructive actions
  """
  attr :variant, :string, default: "primary", values: ~w(primary secondary danger)
  attr :type, :string, default: "button"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled name value form href navigate patch method download)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns = assign(assigns, :computed_class, [button_class(assigns.variant), assigns.class])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={[@computed_class, "no-underline"]} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button type={@type} class={@computed_class} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  defp button_class("primary"),
    do:
      "rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white transition-colors hover:bg-(--admin-accent-hover) focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--admin-accent)"

  defp button_class("secondary"),
    do:
      "rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] transition-colors hover:bg-(--admin-accent-soft) focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--admin-accent)"

  defp button_class("danger"),
    do:
      "rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) transition-colors hover:bg-(--admin-accent-soft) focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--admin-accent)"

  @doc "Consistent destructive button used in admin edit drawers."
  attr :event, :string, required: true
  attr :id, :any, default: nil
  attr :confirm, :string, required: true
  attr :label, :string, default: "Delete"

  def delete_button(assigns) do
    ~H"""
    <.button variant="danger" phx-click={@event} phx-value-id={@id} data-confirm={@confirm}>
      {@label}
    </.button>
    """
  end

  @doc """
  The shared edit-drawer footer: pinned to the bottom of the drawer with a top
  divider (full-bleed via `-mx-5` to cancel the drawer's padding). An optional
  Delete on the left, a spacer, an optional Cancel link, then the caller's primary
  action(s) in the slot (a `save_button`, or the post publish toggles).
  """
  attr :cancel_path, :string, default: nil
  attr :deletable?, :boolean, default: false
  attr :delete_event, :string, default: nil
  attr :delete_id, :any, default: nil
  attr :delete_confirm, :string, default: nil
  slot :inner_block, required: true

  def drawer_footer(assigns) do
    ~H"""
    <div class="mt-auto -mx-5 flex items-center gap-2 border-t border-(--admin-border) px-5 pt-4">
      <.delete_button
        :if={@deletable?}
        event={@delete_event}
        id={@delete_id}
        confirm={@delete_confirm}
      />
      <div class="flex-1"></div>
      <.link
        :if={@cancel_path}
        patch={@cancel_path}
        class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
      >
        Cancel
      </.link>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "The primary submit button used in edit-drawer footers."
  attr :label, :string, default: "Save"

  def save_button(assigns) do
    ~H"""
    <.button type="submit">{@label}</.button>
    """
  end

  defp field_class do
    "w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-3 py-2 text-[0.85rem] text-(--admin-text) focus:border-(--admin-accent) focus:outline-none"
  end

  attr :title, :string, required: true
  slot :inner_block

  def page_header(assigns) do
    ~H"""
    <div class="mb-6 flex items-center justify-between">
      <h1 class="text-[1.35rem] font-semibold tracking-tight">{@title}</h1>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true

  def section_header(assigns) do
    ~H"""
    <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
      {@title}
    </h2>
    """
  end

  @doc """
  The CodeMirror body editor shared by the post and page editors: the hidden
  textarea the `MarkdownEditor` hook mirrors into, the hook element carrying the
  server's upload limits, and the inline-image file input with its errors.

  `key` names the region. Its DOM is `phx-update="ignore"`, so the caller changes
  the key when it swaps in a different record to force morphdom to rebuild it.
  """
  attr :key, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :upload, Phoenix.LiveView.UploadConfig, required: true

  def markdown_editor(assigns) do
    ~H"""
    <div id={"body-editor-#{@key}"} phx-update="ignore">
      <textarea id={"markdown-source-#{@key}"} name={@field.name} class="hidden"><%= Phoenix.HTML.Form.normalize_value("textarea", @field.value) %></textarea>
      <div
        id={"markdown-editor-#{@key}"}
        phx-hook="MarkdownEditor"
        data-input-id={"markdown-source-#{@key}"}
        data-upload-accept={@upload.accept}
        data-upload-max-entries={@upload.max_entries}
        data-upload-max-file-size={@upload.max_file_size}
        class="overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-surface)"
      >
        <div
          data-editor-skeleton
          aria-hidden="true"
          class="flex min-h-[24rem] flex-col gap-5 px-[1.75rem] py-[1.5rem] motion-safe:animate-pulse"
        >
          <div class="h-4 w-1/3 rounded bg-(--admin-border)"></div>
          <div class="h-4 w-full rounded bg-(--admin-border)"></div>
          <div class="h-4 w-5/6 rounded bg-(--admin-border)"></div>
          <div class="h-4 w-2/3 rounded bg-(--admin-border)"></div>
        </div>
      </div>
    </div>

    <.live_file_input upload={@upload} class="sr-only" />
    <p :for={err <- upload_errors(@upload)} class="mt-2 text-[0.78rem] text-red-400">
      Upload failed: {upload_error_message(err)}
    </p>
    <%= for entry <- @upload.entries, err <- upload_errors(@upload, entry) do %>
      <p class="mt-2 text-[0.78rem] text-red-400">
        {entry.client_name}: {upload_error_message(err)}
      </p>
    <% end %>
    """
  end

  defp upload_error_message(:too_large), do: "file too large"
  defp upload_error_message(:not_accepted), do: "unsupported file type"
  defp upload_error_message(:too_many_files), do: "too many files"
  defp upload_error_message(other), do: to_string(other)

  attr :id, :string, required: true
  attr :empty, :string, required: true
  slot :inner_block, required: true

  def list(assigns) do
    ~H"""
    <div
      id={@id}
      phx-update="stream"
      class="overflow-hidden rounded-xl border border-(--admin-border)"
    >
      <div
        id={"#{@id}-empty"}
        class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
      >
        {@empty}
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  slot :leading
  slot :inner_block, required: true
  slot :inline
  slot :meta

  def list_item(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
    >
      {render_slot(@leading)}
      <div class="flex min-w-0 flex-1 items-baseline gap-2">
        <.link
          {link_attrs(@navigate, @patch)}
          class="text-[0.9rem] font-medium text-(--admin-text) no-underline after:absolute after:inset-0"
        >
          {render_slot(@inner_block)}
        </.link>
        {render_slot(@inline)}
      </div>
      <span :for={meta <- @meta} class="contents whitespace-nowrap">{render_slot(meta)}</span>
    </div>
    """
  end

  defp link_attrs(nil, nil), do: %{}
  defp link_attrs(nil, patch), do: %{patch: patch}
  defp link_attrs(navigate, _patch), do: %{navigate: navigate}

  @doc "A bordered settings list row: title + meta line on the left, action on the right."
  attr :id, :string, required: true
  slot :title, required: true
  slot :meta, required: true
  slot :action, required: true

  def settings_row(assigns) do
    ~H"""
    <li
      id={@id}
      class="flex items-center justify-between rounded-md border border-(--admin-border) px-3 py-2"
    >
      <div>
        <div class="text-[0.85rem] text-(--admin-text)">{render_slot(@title)}</div>
        <div class="text-[0.72rem] text-(--admin-text-subtle)">{render_slot(@meta)}</div>
      </div>
      {render_slot(@action)}
    </li>
    """
  end
end
