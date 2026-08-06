# frozen_string_literal: true

class EnforceOneCorporateLoginPerAccount < ActiveRecord::Migration[8.0]
  INDEX_NAME = "index_users_on_unique_corporate_account"

  def change
    add_index :users,
      :account_id,
      unique: true,
      where: "role = 'corporate'",
      name: INDEX_NAME
  end
end
