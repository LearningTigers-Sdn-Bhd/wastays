# frozen_string_literal: true

# A folio's identity is its formatted reference (`WSTY-3000042/1`), not a text
# name. The old `name` column was doing two jobs at once: `assign_defaults`
# persisted a generated placeholder ("Guest Folio", "Folio 42") at create time,
# and staff could overwrite the same column with a real name. Nothing could tell
# the two apart, so raw folio integers ended up baked into rows and rendered in
# dialog titles, dropdowns and reports.
#
# After this migration the column is `label`: nullable, never auto-filled, set
# only when a human deliberately names a folio. A folio with no label displays
# its reference.
class RenameBookingFolioNameToLabel < ActiveRecord::Migration[8.0]
  # Every value the app used to generate. Party-derived names ("Acme Corp Folio",
  # "Jane Tan Folio") are handled separately since they depend on the linked row.
  GENERATED_NAMES = [
    "Guest Folio",
    "Agent Folio",
    "House Folio",
    "External Folio",
    "Company Folio",
    "Folio"
  ].freeze

  def up
    rename_column :booking_folios, :name, :label
    change_column_null :booking_folios, :label, true

    cleared = clear_generated_labels!
    say "Cleared #{cleared} generated folio label(s); folios now display their reference", true
  end

  def down
    execute(<<~SQL)
      UPDATE booking_folios
      SET label = 'Folio ' || folio_number
      WHERE label IS NULL
    SQL

    change_column_null :booking_folios, :label, false
    rename_column :booking_folios, :label, :name
  end

  private

  # A rename_folio log proves a human set the label, so those are always kept.
  # Everything else is cleared when it matches a shape the app used to generate.
  def clear_generated_labels!
    quoted = GENERATED_NAMES.map { |value| quote(value) }.join(", ")

    generic = execute(<<~SQL).cmd_tuples
      UPDATE booking_folios
      SET label = NULL, updated_at = NOW()
      WHERE label IS NOT NULL
        AND (label IN (#{quoted}) OR label ~ '^Folio [0-9]+$')
        AND id NOT IN (#{renamed_folio_ids_sql})
    SQL

    generic + clear_party_derived_labels!
  end

  # `BookingWorkspaces::CreateFolioWindow` named folios after the billing party:
  # "<guest name> Folio" for guests, the company name itself for companies.
  def clear_party_derived_labels!
    candidates = select_all(<<~SQL)
      SELECT f.id, f.label, p.party_kind,
             COALESCE(bg.name_snapshot, g.name, b.guest_name) AS guest_name,
             ca.name AS company_name
      FROM booking_folios f
      JOIN booking_billing_parties p ON p.id = f.booking_billing_party_id
      JOIN bookings b ON b.id = f.booking_id
      LEFT JOIN booking_guests bg ON bg.id = p.booking_guest_id
      LEFT JOIN guests g ON g.id = bg.guest_id
      LEFT JOIN hotel_corporate_accounts hca ON hca.id = p.hotel_corporate_account_id
      LEFT JOIN accounts ca ON ca.id = hca.corporate_account_id
      WHERE f.label IS NOT NULL
        AND f.id NOT IN (#{renamed_folio_ids_sql})
    SQL

    derived_ids = candidates.filter_map do |row|
      generated =
        case row["party_kind"]
        when "guest" then [ "#{row['guest_name']} Folio" ]
        when "company" then [ row["company_name"], "#{row['company_name']} Folio" ]
        else []
        end

      row["id"] if generated.compact_blank.include?(row["label"])
    end
    return 0 if derived_ids.empty?

    execute("UPDATE booking_folios SET label = NULL, updated_at = NOW() WHERE id IN (#{derived_ids.join(', ')})")
    derived_ids.size
  end

  def renamed_folio_ids_sql
    <<~SQL.squish
      SELECT COALESCE(target_folio_id, source_folio_id)
      FROM folio_operation_logs
      WHERE operation_type = 'rename_folio'
        AND COALESCE(target_folio_id, source_folio_id) IS NOT NULL
    SQL
  end
end
