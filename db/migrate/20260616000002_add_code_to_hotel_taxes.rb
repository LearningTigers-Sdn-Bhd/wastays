# frozen_string_literal: true

class AddCodeToHotelTaxes < ActiveRecord::Migration[8.0]
  class MigrationHotelTax < ActiveRecord::Base
    self.table_name = "hotel_taxes"
    belongs_to :transaction_code, class_name: "AddCodeToHotelTaxes::MigrationTransactionCode", optional: true
  end

  class MigrationTransactionCode < ActiveRecord::Base
    self.table_name = "transaction_codes"
  end

  def up
    add_column :hotel_taxes, :code, :string

    backfill_codes

    add_index :hotel_taxes, [ :hotel_id, :code ], unique: true, where: "code IS NOT NULL"
  end

  def down
    remove_index :hotel_taxes, [ :hotel_id, :code ]
    remove_column :hotel_taxes, :code
  end

  private

  def backfill_codes
    MigrationHotelTax.order(:hotel_id, :id).find_each do |tax|
      code = unique_code_for(tax)
      tax.update_columns(code: code, updated_at: Time.current)

      next unless tax.transaction_code

      tax.transaction_code.update_columns(code: "TAX_#{code}", name: tax.name, updated_at: Time.current)
    end
  end

  def unique_code_for(tax)
    base = normalized_code(tax.transaction_code&.code.to_s.delete_prefix("TAX_"))
    base = normalized_code(tax.name) if base.blank?
    base = abbreviation_from_name(tax.name) if base.length > 12
    base = "CUSTOM" if base.blank?
    code = base
    suffix = 2

    while code_taken?(tax, code)
      code = "#{base}#{suffix}"
      suffix += 1
    end

    code
  end

  def code_taken?(tax, code)
    MigrationHotelTax.where(hotel_id: tax.hotel_id, code: code).where.not(id: tax.id).exists? ||
      MigrationTransactionCode.where(hotel_id: tax.hotel_id, code: "TAX_#{code}").where.not(id: tax.transaction_code_id).exists?
  end

  def normalized_code(value)
    value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
  end

  def abbreviation_from_name(name)
    words = name.to_s.scan(/[A-Za-z0-9]+/)
    abbreviation = if words.length > 1
      words.map { |word| word[0] }.join
    else
      words.first.to_s[0, 4]
    end

    normalized_code(abbreviation)
  end
end
