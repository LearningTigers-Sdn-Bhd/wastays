# frozen_string_literal: true

# The retired Transaction Codes page let staff create custom charge codes that
# nothing could then post against — the folio charge form reads
# hotel_extra_charges, not transaction_codes. Any code created that way is an
# orphan: visible in the ledger, unusable at the front desk, and now with no page
# to edit it from.
#
# Wrapping each one as a hotel_extra_charges row makes it both manageable (Extra
# Charges owns it) and postable, without touching the code itself — so GL
# mappings, reports, and already-posted transactions are unaffected.
class WrapOrphanCustomChargeCodesAsExtraCharges < ActiveRecord::Migration[8.0]
  class MigrationTransactionCode < ActiveRecord::Base
    self.table_name = "transaction_codes"
  end

  class MigrationExtraCharge < ActiveRecord::Base
    self.table_name = "hotel_extra_charges"
  end

  class MigrationDiscount < ActiveRecord::Base
    self.table_name = "hotel_discounts"
  end

  class MigrationPaymentMethod < ActiveRecord::Base
    self.table_name = "hotel_payment_methods"
  end

  class MigrationHotelTax < ActiveRecord::Base
    self.table_name = "hotel_taxes"
  end

  class MigrationReservationPolicy < ActiveRecord::Base
    self.table_name = "hotel_reservation_policies"
  end

  def up
    now = Time.current
    positions = starting_positions

    orphan_charge_codes.find_each do |code|
      positions[code.hotel_id] += 1
      MigrationExtraCharge.create!(
        hotel_id: code.hotel_id,
        transaction_code_id: code.id,
        # Manual pricing preserves what these codes did before: staff name the
        # amount. Nothing about the code's own configuration changes.
        pricing_type: "manual",
        charging_unit: "per_item",
        allow_amount_override: true,
        position: positions[code.hotel_id],
        created_at: now,
        updated_at: now
      )
    end
  end

  # Deliberately irreversible in the data sense: the wrapper rows are now the only
  # way staff can post these codes, so dropping them would re-orphan the codes.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def orphan_charge_codes
    MigrationTransactionCode
      .where(kind: "charge", system_required: false)
      .where.not(category: %w[tax security_deposit])
      .where.not(id: MigrationExtraCharge.select(:transaction_code_id))
      .where.not(id: MigrationDiscount.select(:transaction_code_id))
      .where.not(id: MigrationPaymentMethod.select(:transaction_code_id))
      .where.not(id: MigrationHotelTax.where.not(transaction_code_id: nil).select(:transaction_code_id))
      .where.not(id: MigrationReservationPolicy.select(:transaction_code_id))
      .order(:hotel_id, :id)
  end

  def starting_positions
    Hash.new(0).merge(MigrationExtraCharge.group(:hotel_id).maximum(:position).transform_values(&:to_i))
  end
end
