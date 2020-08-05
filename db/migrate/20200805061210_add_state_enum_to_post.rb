# frozen_string_literal: true

class AddStateEnumToPost < ActiveRecord::Migration[6.0]
  def change
    add_column :posts, :state, :integer, default: 0
    add_index :posts, :slug, unique: true
  end
end
