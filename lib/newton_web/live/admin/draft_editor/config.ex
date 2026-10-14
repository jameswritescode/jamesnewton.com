defmodule NewtonWeb.Admin.DraftEditor.Config do
  @moduledoc """
  What `NewtonWeb.Admin.DraftEditor` needs to know about one kind of record:
  the assign it lives in, its context functions, the fields it autosaves, the
  field derived from its body, its untitled placeholder identity, how to tell
  it is published, and what to do after each write.
  """

  @enforce_keys [
    :record,
    :change,
    :create,
    :update,
    :attach_image,
    :autosave_fields,
    :derived_field,
    :placeholder_title,
    :untitled_slug_prefix,
    :next_untitled_slug,
    :published?,
    :editing_published?,
    :notify,
    :edit_path,
    :load_saved
  ]
  defstruct @enforce_keys

  @type draft :: struct()

  @typedoc """
  * `record` - the assign holding the record being edited
  * `derived_field` - the field that follows the body until the author edits it
  * `published?` - is a loaded record published (its slug is then locked)?
  * `editing_published?` - is the record on screen published, judged from assigns?
  * `notify` - called with the record before and after every write
  * `load_saved` - loads a just-created record into the editor
  """
  @type t :: %__MODULE__{
          record: atom(),
          change: (draft(), map() -> Ecto.Changeset.t()),
          create: (map() -> {:ok, draft()} | {:error, Ecto.Changeset.t()}),
          update: (draft(), map() -> {:ok, draft()} | {:error, Ecto.Changeset.t() | :stale}),
          attach_image: (draft(), String.t(), String.t() -> term()),
          autosave_fields: [String.t()],
          derived_field: atom(),
          placeholder_title: String.t(),
          untitled_slug_prefix: String.t(),
          next_untitled_slug: (-> String.t()),
          published?: (draft() -> boolean()),
          editing_published?: (map() -> boolean()),
          notify: (draft() | nil, draft() | nil -> term()),
          edit_path: (draft() -> String.t()),
          load_saved: (Phoenix.LiveView.Socket.t(), draft() -> Phoenix.LiveView.Socket.t())
        }
end
