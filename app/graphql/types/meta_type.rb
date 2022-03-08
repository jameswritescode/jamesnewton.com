# frozen_string_literal: true

module Types
  class MetaType < BaseObject
    field :description, String, null: false
    field :title, String, null: false
    field :type, String, null: false
  end
end
