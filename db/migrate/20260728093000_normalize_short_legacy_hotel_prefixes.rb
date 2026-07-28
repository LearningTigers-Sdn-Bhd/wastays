# frozen_string_literal: true

class NormalizeShortLegacyHotelPrefixes < ActiveRecord::Migration[8.0]
  def up
    rows = select_rows("SELECT id, hotel_prefix FROM hotels WHERE LENGTH(hotel_prefix) < 3 ORDER BY id")
    return if rows.empty?

    used = select_values("SELECT hotel_prefix FROM hotels WHERE LENGTH(hotel_prefix) >= 3").to_set
    rows.each do |id, old_prefix|
      prefix = old_prefix.to_s.ljust(1, "H").then { |value| "#{value.first}#{value[1..].to_s.rjust(2, '0')}" }
      prefix = "H#{SecureRandom.alphanumeric(5).upcase}" while used.include?(prefix)
      used << prefix

      execute "UPDATE hotels SET hotel_prefix = #{quote(prefix)} WHERE id = #{quote(id)}"
      execute "UPDATE hotel_prefix_histories SET prefix = #{quote(prefix)} WHERE hotel_id = #{quote(id)} AND prefix = #{quote(old_prefix)}"
      refresh_reference_snapshots!(id, prefix)
    end
  end

  def down
    # Public reference snapshots must not be shortened again.
  end

  private

  def refresh_reference_snapshots!(hotel_id, prefix)
    execute <<~SQL.squish
      UPDATE bookings SET
        reservation_reference = CASE WHEN reservation_number IS NULL THEN NULL ELSE #{quote(prefix)} || '-1' || LPAD(reservation_number::text, 7, '0') END,
        guest_registration_reference = CASE WHEN guest_registration_number IS NULL THEN NULL ELSE #{quote(prefix)} || '-2' || LPAD(guest_registration_number::text, 7, '0') END,
        folio_account_reference = CASE WHEN folio_account_reference IS NULL THEN NULL ELSE #{quote(prefix)} || SUBSTRING(folio_account_reference FROM POSITION('-' IN folio_account_reference)) END,
        tourism_tax_voucher_reference = CASE WHEN tourism_tax_voucher_number IS NULL THEN NULL ELSE #{quote(prefix)} || '-6' || LPAD(tourism_tax_voucher_number::text, 7, '0') END
      WHERE hotel_id = #{quote(hotel_id)}
    SQL
    execute <<~SQL.squish
      UPDATE group_bookings SET reservation_reference = #{quote(prefix)} || '-1' || LPAD(reservation_number::text, 7, '0')
      WHERE hotel_id = #{quote(hotel_id)}
    SQL
    execute <<~SQL.squish
      UPDATE booking_folios SET invoice_reference = CASE WHEN invoice_number IS NULL THEN NULL ELSE #{quote(prefix)} || '-7' || LPAD(invoice_number::text, 7, '0') END
      WHERE hotel_id = #{quote(hotel_id)}
    SQL
    execute <<~SQL.squish
      UPDATE ar_invoices SET invoice_reference = #{quote(prefix)} || '-4' || LPAD(invoice_number::text, 7, '0')
      WHERE hotel_id = #{quote(hotel_id)}
    SQL
  end
end
