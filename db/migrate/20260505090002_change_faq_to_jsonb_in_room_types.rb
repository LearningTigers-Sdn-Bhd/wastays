class ChangeFaqToJsonbInRoomTypes < ActiveRecord::Migration[7.1]
  def up
    remove_column :room_types, :faq, :text
  end

  def down
    add_column :room_types, :faq, :text
  end
end
