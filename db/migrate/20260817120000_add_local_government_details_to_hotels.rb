# frozen_string_literal: true

class AddLocalGovernmentDetailsToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :local_government_name, :string
    add_column :hotels, :local_government_license_number, :string
  end
end
