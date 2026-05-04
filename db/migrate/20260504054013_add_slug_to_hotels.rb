class AddSlugToHotels < ActiveRecord::Migration[8.0]
  class MigrationHotel < ApplicationRecord
    self.table_name = "hotels"
  end

  def up
    add_column :hotels, :slug, :string
    add_index :hotels, :slug, unique: true

    say_with_time "Backfilling hotel slugs" do
      MigrationHotel.reset_column_information
      MigrationHotel.find_each do |hotel|
        next if hotel.slug.present?

        base_slug = hotel.name.to_s.parameterize.presence || "hotel"
        slug = base_slug
        suffix = 2

        while MigrationHotel.where.not(id: hotel.id).exists?(slug: slug)
          slug = "#{base_slug}-#{suffix}"
          suffix += 1
        end

        hotel.update_columns(slug: slug)
      end
    end

    change_column_null :hotels, :slug, false
  end

  def down
    remove_index :hotels, :slug
    remove_column :hotels, :slug
  end
end
