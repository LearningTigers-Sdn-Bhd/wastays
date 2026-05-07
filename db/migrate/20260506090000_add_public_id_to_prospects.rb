class AddPublicIdToProspects < ActiveRecord::Migration[8.0]
  def up
    add_column :prospects, :public_id, :string

    say_with_time "Backfilling prospect public IDs" do
      Prospect.reset_column_information
      Prospect.find_each do |prospect|
        prospect.update_columns(public_id: unique_public_id)
      end
    end

    change_column_null :prospects, :public_id, false
    add_index :prospects, :public_id, unique: true
  end

  def down
    remove_index :prospects, :public_id
    remove_column :prospects, :public_id
  end

  private

  def unique_public_id
    loop do
      public_id = "prsp_#{SecureRandom.urlsafe_base64(18).tr('-_', '').downcase}"
      return public_id unless Prospect.exists?(public_id: public_id)
    end
  end
end
