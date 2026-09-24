class CreateConciergeStayAccesses < ActiveRecord::Migration[8.0]
  def change
    create_table :concierge_stay_accesses do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true

      # The link the guest opens. Random, so it carries no database id and no
      # confirmation code.
      t.string :stay_access_id, null: false

      t.datetime :revoked_at

      # The attempt limit belongs to the stay, not to one browser. A guest who
      # changes device keeps the same budget.
      t.integer :attempt_count, null: false, default: 0
      t.datetime :attempt_window_started_at
      t.datetime :last_attempt_at
      t.datetime :locked_until

      t.timestamps
    end

    add_index :concierge_stay_accesses, :stay_access_id, unique: true

    # One live link for one booking. A revoked record stays for the audit trail,
    # so the uniqueness covers the live rows only.
    add_index :concierge_stay_accesses, :booking_id,
      unique: true,
      where: "revoked_at IS NULL",
      name: "index_concierge_stay_accesses_on_live_booking"
  end
end
