# frozen_string_literal: true

class AddAgentFieldsToUsers < ActiveRecord::Migration[8.0]
  # Letters and digits that cannot be misread for each other (no 0/O, 1/I).
  CODE_CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze

  def up
    add_column :users, :agent_code, :string
    add_column :users, :can_create_hotels, :boolean, default: false, null: false
    add_index :users, :agent_code, unique: true

    # Every super agent needs a code for the invite link.
    select_values("SELECT id FROM users WHERE role = 'super_agent' AND agent_code IS NULL").each do |id|
      code = Array.new(6) { CODE_CHARACTERS.sample }.join
      execute "UPDATE users SET agent_code = #{connection.quote(code)} WHERE id = #{id.to_i}"
    end
  end

  def down
    remove_index :users, :agent_code
    remove_column :users, :can_create_hotels
    remove_column :users, :agent_code
  end
end
