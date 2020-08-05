# frozen_string_literal: true

module Types
  class PostType < BaseObject
    implements NodeType

    def self.scope_items(items, context)
      return items.published if context[:current_user].blank?

      items
    end

    field :content, String, null: false
    field :created, String, null: false
    field :name, String, null: false
    field :slug, String, null: false
    field :state, PostStateType, null: false
    field :url, String, null: false

    field :meta, MetaType, null: false
    def meta
      object.meta(context[:controller])
    end
  end
end
