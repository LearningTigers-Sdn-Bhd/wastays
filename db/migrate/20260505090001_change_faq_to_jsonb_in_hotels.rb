class ChangeFaqToJsonbInHotels < ActiveRecord::Migration[7.1]
  def up
    # Discard existing data by explicitly casting to empty array
    execute "UPDATE hotels SET faq = '[]'::jsonb"
    
    change_column :hotels, :faq, :jsonb, using: "faq::jsonb", default: [], null: false
  end

  def down
    change_column :hotels, :faq, :text
  end
end
