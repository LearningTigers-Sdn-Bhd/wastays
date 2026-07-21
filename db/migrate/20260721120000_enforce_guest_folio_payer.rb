# frozen_string_literal: true

# Backend fix backstop: a guest-type folio must always be guest-payer.
#
# The model already coerces this (`normalize_payer_type`: folio_type "guest" =>
# payer_type "guest"), but the old "bill to company" path bypassed it with a raw
# `update_all`, flipping the guest folio's payer_type to "company" and hijacking
# it onto the company party. Room charges are now *routed* to the sponsor's own
# (external) folio, so the guest folio is never corrupted.
#
# This constraint mirrors the app rule at the database level so no path —
# including raw SQL — can billed a guest-type folio to a company. It does NOT
# constrain external folios, so the legitimate "external company folio as
# primary" feature (Folios::CreateFolio set_folio_as_primary) is unaffected.
class EnforceGuestFolioPayer < ActiveRecord::Migration[8.0]
  CONSTRAINT = "booking_folios_guest_type_is_guest_payer"

  def up
    repair_polluted_guest_folios!

    add_check_constraint :booking_folios,
      "folio_type <> 'guest' OR payer_type = 'guest'",
      name: CONSTRAINT
  end

  def down
    remove_check_constraint :booking_folios, name: CONSTRAINT
  end

  private

  def repair_polluted_guest_folios!
    polluted = select_all(<<~SQL)
      SELECT id, booking_id
      FROM booking_folios
      WHERE folio_type = 'guest' AND payer_type <> 'guest'
    SQL

    polluted.each do |folio|
      # Relink to the booking's guest billing party only when unambiguous;
      # otherwise leave it null, matching the app's legacy-folio handling.
      guest_party_count = select_value(<<~SQL).to_i
        SELECT COUNT(*) FROM booking_billing_parties
        WHERE booking_id = #{folio["booking_id"].to_i}
          AND party_kind = 'guest' AND archived_at IS NULL
      SQL
      relink_id =
        if guest_party_count == 1
          select_value(<<~SQL).to_i
            SELECT id FROM booking_billing_parties
            WHERE booking_id = #{folio["booking_id"].to_i}
              AND party_kind = 'guest' AND archived_at IS NULL
            LIMIT 1
          SQL
        else
          "NULL"
        end

      execute(<<~SQL)
        UPDATE booking_folios
        SET payer_type = 'guest',
            hotel_corporate_account_id = NULL,
            booking_billing_party_id = #{relink_id},
            updated_at = NOW()
        WHERE id = #{folio["id"].to_i}
      SQL
    end

    say "Repaired #{polluted.count} polluted guest folio(s) back to guest payer", true
  end
end
