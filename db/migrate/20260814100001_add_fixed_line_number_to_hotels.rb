# frozen_string_literal: true

# Most properties answer a landline at the front desk, which is a different
# number from the mobile a manager carries, so it gets its own column.
class AddFixedLineNumberToHotels < ActiveRecord::Migration[8.1]
  def change
    add_column :hotels, :fixed_line_number, :string
  end
end
