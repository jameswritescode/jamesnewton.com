# frozen_string_literal: true

module Types
  class PostType < BaseObject
    implements NodeType

    global_id_field :id

    def self.scope_items(items, context)
      if context[:controller]&.current_user.blank?
        items.published_desc
      else
        items.order(created_at: :desc)
      end
    end

    field :attachments, [Types::AttachmentType], null: true
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
