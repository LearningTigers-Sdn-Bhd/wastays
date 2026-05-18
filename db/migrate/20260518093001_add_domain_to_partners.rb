class AddDomainToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :domain, :string
    add_index :partners, :domain
  end
end
