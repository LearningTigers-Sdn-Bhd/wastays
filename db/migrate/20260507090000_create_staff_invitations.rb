# frozen_string_literal: true

class CreateStaffInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_invitations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :hotel, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.references :invited_by_user, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.string :name
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at

      t.timestamps
    end

    add_index :staff_invitations, :token_digest, unique: true
    add_index :staff_invitations, [ :hotel_id, :email ], unique: true, where: "accepted_at IS NULL", name: "index_pending_staff_invites_on_hotel_and_email"
    add_index :staff_invitations, :accepted_at
    add_index :staff_invitations, :expires_at
  end
end
