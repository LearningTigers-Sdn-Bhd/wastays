class AddBodyToMailEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :mail_events, :body, :text
  end
end
