# frozen_string_literal: true

class CreateBookingBillingTerms < ActiveRecord::Migration[8.0]
  def up
    create_table :booking_billing_terms do |t|
      t.references :booking_billing_party, null: false, foreign_key: true, index: { unique: true }
      t.string :settlement_type, null: false, default: "cash_bank"
      t.string :preferred_payment_method
      t.string :purchase_order_reference
      t.string :billing_reference
      t.string :authorization_reference
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_check_constraint :booking_billing_terms,
      "settlement_type IN ('cash_bank', 'city_ledger')",
      name: "booking_billing_terms_settlement_allowed"

    backfill_terms
  end

  def down
    drop_table :booking_billing_terms
  end

  private

  def backfill_terms
    execute <<~SQL.squish
      INSERT INTO booking_billing_terms (
        booking_billing_party_id,
        settlement_type,
        created_at,
        updated_at
      )
      SELECT
        booking_billing_parties.id,
        'cash_bank',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM booking_billing_parties
    SQL

    execute <<~SQL.squish
      UPDATE booking_billing_terms
      SET
        settlement_type = arrangement_terms.settlement_type,
        preferred_payment_method = arrangement_terms.preferred_payment_method,
        purchase_order_reference = arrangement_terms.purchase_order_reference,
        billing_reference = arrangement_terms.billing_reference,
        authorization_reference = arrangement_terms.authorization_reference,
        updated_at = CURRENT_TIMESTAMP
      FROM (
        SELECT
          booking_billing_parties.id AS booking_billing_party_id,
          MIN(group_billing_arrangements.settlement_type) AS settlement_type,
          MIN(group_billing_arrangements.preferred_payment_method) AS preferred_payment_method,
          MIN(group_billing_arrangements.purchase_order_reference) AS purchase_order_reference,
          MIN(group_billing_arrangements.billing_reference) AS billing_reference,
          MIN(group_billing_arrangements.authorization_reference) AS authorization_reference
        FROM booking_billing_parties
        INNER JOIN booking_billing_assignments
          ON booking_billing_assignments.booking_id = booking_billing_parties.booking_id
        INNER JOIN group_billing_arrangements
          ON group_billing_arrangements.id = booking_billing_assignments.group_billing_arrangement_id
        WHERE booking_billing_parties.party_kind = 'company'
          AND group_billing_arrangements.payer_type = 'company'
          AND group_billing_arrangements.hotel_corporate_account_id = booking_billing_parties.hotel_corporate_account_id
        GROUP BY booking_billing_parties.id
        HAVING COUNT(DISTINCT group_billing_arrangements.id) = 1
      ) arrangement_terms
      WHERE booking_billing_terms.booking_billing_party_id = arrangement_terms.booking_billing_party_id
    SQL
  end
end
