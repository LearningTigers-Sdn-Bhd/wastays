# frozen_string_literal: true

# Splits the old "ic" document type into "malaysian_nric" and "national_id",
# and gives a guest one place to hold a passport number. A foreign guest who
# holds a national identity card must give a passport number, because LHDN
# accepts only a MyKad or a passport on an individual e-invoice.
class AddGuestPassportNumbers < ActiveRecord::Migration[8.0]
  def up
    add_column :guests, :passport_number, :string
    add_column :guests, :passport_issuing_country_code, :string, limit: 3
    add_column :booking_guests, :passport_number_snapshot, :string
    add_column :booking_guests, :passport_issuing_country_code_snapshot, :string, limit: 3

    add_index :guests, :passport_number, name: "index_guests_on_passport_number"

    rename_document_type(:guests, :document_type, :country)
    rename_document_type(:booking_guests, :document_type_snapshot, :country_snapshot)
  end

  def down
    remove_index :guests, name: "index_guests_on_passport_number"
    remove_column :booking_guests, :passport_issuing_country_code_snapshot
    remove_column :booking_guests, :passport_number_snapshot
    remove_column :guests, :passport_issuing_country_code
    remove_column :guests, :passport_number

    restore_document_type(:guests, :document_type)
    restore_document_type(:booking_guests, :document_type_snapshot)
  end

  private

  def rename_document_type(table, type_column, country_column)
    execute(<<~SQL.squish)
      UPDATE #{table}
      SET #{type_column} = CASE
        WHEN lower(coalesce(#{country_column}, '')) IN ('malaysia', 'my', 'mys') OR #{country_column} IS NULL
          THEN 'malaysian_nric'
        ELSE 'national_id'
      END
      WHERE lower(#{type_column}) = 'ic'
    SQL
  end

  def restore_document_type(table, type_column)
    execute(<<~SQL.squish)
      UPDATE #{table}
      SET #{type_column} = 'ic'
      WHERE #{type_column} IN ('malaysian_nric', 'national_id')
    SQL
  end
end
