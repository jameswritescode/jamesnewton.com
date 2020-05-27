# frozen_string_literal: true

class CreatePosts < ActiveRecord::Migration[6.0]
  def change
    create_table :posts do |t|
      t.string :name
      t.string :slug
      t.text :content
    end
  end
end
