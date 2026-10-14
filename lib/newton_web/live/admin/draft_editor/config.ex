defmodule NewtonWeb.Admin.DraftEditor.Config do
  @moduledoc """
  What `NewtonWeb.Admin.DraftEditor` needs to know about one kind of record:
  the assign it lives in, its context functions, the fields it autosaves, the
  field derived from its body, its untitled placeholder identity, how to tell
  it is published, and what to do after each write.
  """

  @enforce_keys [
    :record_assign,
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
    :notify,
    :edit_path,
    :load_saved
  ]
  defstruct @enforce_keys

  @type draft :: struct()

  @typedoc """
  * `record_assign` - the assign holding the record being edited
  * `change` - builds the record's changeset from form params
  * `create` - inserts a new record from params
  * `update` - updates a record from params, `{:error, :stale}` when another
    window saved first
  * `attach_image` - records an uploaded image key on the record's image ledger
  * `autosave_fields` - the content fields a draft autosaves
  * `derived_field` - the field that follows the body until the author edits it
  * `placeholder_title` - the title an untitled draft is created with
  * `untitled_slug_prefix` - the series (`prefix`, `prefix-2`, …) untitled
    drafts' generated slugs belong to
  * `next_untitled_slug` - the next free slug in that series
  * `published?` - is the record published? Its slug is then locked and it is
    no longer autosaved
  * `notify` - called with the record before and after every write
  * `edit_path` - the record's edit URL, patched to after a create
  * `load_saved` - loads a just-created record into the editor
  """
  @type t :: %__MODULE__{
          record_assign: atom(),
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
          notify: (draft() | nil, draft() | nil -> term()),
          edit_path: (draft() -> String.t()),
          load_saved: (Phoenix.LiveView.Socket.t(), draft() -> Phoenix.LiveView.Socket.t())
        }
end
