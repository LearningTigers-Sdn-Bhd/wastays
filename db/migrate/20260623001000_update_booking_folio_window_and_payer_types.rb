# frozen_string_literal: true

class UpdateBookingFolioWindowAndPayerTypes < ActiveRecord::Migration[8.0]
  FOLIO_TYPE_CONSTRAINT = "booking_folios_folio_type_allowed"
  PAYER_TYPE_CONSTRAINT = "booking_folios_payer_type_allowed"

  def up
    remove_check_constraint :booking_folios, name: FOLIO_TYPE_CONSTRAINT
    remove_check_constraint :booking_folios, name: PAYER_TYPE_CONSTRAINT

    execute <<~SQL.squish
      UPDATE booking_folios
      SET folio_type = 'external'
      WHERE folio_type IN ('company', 'custom', 'group', 'master')
    SQL

    execute <<~SQL.squish
      UPDATE booking_folios
      SET payer_type = CASE
        WHEN folio_type = 'guest' THEN 'guest'
        WHEN folio_type = 'house' THEN 'hotel'
        ELSE payer_type
      END
    SQL

    add_check_constraint :booking_folios,
      "folio_type IN ('guest', 'external', 'house')",
      name: FOLIO_TYPE_CONSTRAINT
    add_check_constraint :booking_folios,
      "payer_type IN ('guest', 'company', 'agent', 'hotel', 'custom')",
      name: PAYER_TYPE_CONSTRAINT
  end

  def down
    remove_check_constraint :booking_folios, name: PAYER_TYPE_CONSTRAINT
    remove_check_constraint :booking_folios, name: FOLIO_TYPE_CONSTRAINT

    execute <<~SQL.squish
      UPDATE booking_folios
      SET payer_type = 'custom'
      WHERE payer_type IN ('agent', 'hotel')
    SQL

    execute <<~SQL.squish
      UPDATE booking_folios
      SET folio_type = 'custom'
      WHERE folio_type = 'external'
    SQL

    add_check_constraint :booking_folios,
      "folio_type IN ('guest', 'company', 'custom', 'group', 'master', 'house')",
      name: FOLIO_TYPE_CONSTRAINT
    add_check_constraint :booking_folios,
      "payer_type IN ('guest', 'company', 'custom')",
      name: PAYER_TYPE_CONSTRAINT
  end
end
