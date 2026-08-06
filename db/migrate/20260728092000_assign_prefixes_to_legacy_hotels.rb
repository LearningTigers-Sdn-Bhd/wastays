# frozen_string_literal: true

class AssignPrefixesToLegacyHotels < ActiveRecord::Migration[8.0]
  def up
    hotel_ids = select_values("SELECT id FROM hotels WHERE hotel_prefix IS NULL OR hotel_prefix = '' ORDER BY id")
    return if hotel_ids.empty?

    used = select_values("SELECT hotel_prefix FROM hotels WHERE hotel_prefix IS NOT NULL AND hotel_prefix <> ''").to_set
    hotel_ids.each do |id|
      prefix = "H#{id.to_i.to_s(36).upcase.rjust(2, '0')}"
      prefix = "H#{SecureRandom.alphanumeric(5).upcase}" while used.include?(prefix)
      used << prefix
      execute "UPDATE hotels SET hotel_prefix = #{quote(prefix)} WHERE id = #{quote(id)}"
      execute "DELETE FROM hotel_prefix_histories WHERE hotel_id = #{quote(id)}"
      execute <<~SQL.squish
        INSERT INTO hotel_prefix_histories (hotel_id, prefix, created_at, updated_at)
        VALUES (#{quote(id)}, #{quote(prefix)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end

    refresh_reference_snapshots!(hotel_ids)
  end

  def down
    # Prefixes that have issued public references are intentionally not removed.
  end

  private

  def refresh_reference_snapshots!(hotel_ids)
    ids = hotel_ids.map { |id| quote(id) }.join(",")
    execute <<~SQL.squish
      UPDATE bookings SET
        reservation_reference = CASE WHEN reservation_number IS NULL THEN NULL ELSE hotels.hotel_prefix || '-1' || LPAD(reservation_number::text, 7, '0') END,
        guest_registration_reference = CASE WHEN guest_registration_number IS NULL THEN NULL ELSE hotels.hotel_prefix || '-2' || LPAD(guest_registration_number::text, 7, '0') END,
        folio_account_reference = CASE WHEN folio_account_reference IS NULL THEN NULL ELSE hotels.hotel_prefix || SUBSTRING(folio_account_reference FROM POSITION('-' IN folio_account_reference)) END,
        tourism_tax_voucher_reference = CASE WHEN tourism_tax_voucher_number IS NULL THEN NULL ELSE hotels.hotel_prefix || '-6' || LPAD(tourism_tax_voucher_number::text, 7, '0') END
      FROM hotels WHERE bookings.hotel_id = hotels.id AND hotels.id IN (#{ids})
    SQL
    execute <<~SQL.squish
      UPDATE group_bookings SET
        reservation_reference = hotels.hotel_prefix || '-1' || LPAD(reservation_number::text, 7, '0')
      FROM hotels WHERE group_bookings.hotel_id = hotels.id AND hotels.id IN (#{ids})
    SQL
    execute <<~SQL.squish
      UPDATE booking_folios SET
        invoice_reference = CASE WHEN invoice_number IS NULL THEN NULL ELSE hotels.hotel_prefix || '-7' || LPAD(invoice_number::text, 7, '0') END
      FROM hotels WHERE booking_folios.hotel_id = hotels.id AND hotels.id IN (#{ids})
    SQL
    execute <<~SQL.squish
      UPDATE ar_invoices SET invoice_reference = hotels.hotel_prefix || '-4' || LPAD(invoice_number::text, 7, '0')
      FROM hotels WHERE ar_invoices.hotel_id = hotels.id AND hotels.id IN (#{ids})
    SQL
  end
end
