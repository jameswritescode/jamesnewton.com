# frozen_string_literal: true

module Types
  class PostType < BaseObject
    implements NodeType

    global_id_field :id

    def self.scope_items(items, context)
      if context.current_user.blank?
        items.published_desc
      else
        items.order(state: :asc, created_at: :desc)
      end
    end

    field :content, String, null: false
    field :created, String, null: false
    field :meta, MetaType, null: false
    field :name, String, null: false
    field :slug, String, null: false
    field :state, PostStateType, null: false
    field :url, String, null: false

    field :images, [Types::AttachmentType], null: false
    def images
      object.attachments.select(&:embed?)
    end
  end
end
