class AddFileDataToAttachments < ActiveRecord::Migration[6.0]
  def change
    add_column :attachments, :file_data, :text
  end
end
