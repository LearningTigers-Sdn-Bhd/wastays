# frozen_string_literal: true

class CreateAttractionRegistry < ActiveRecord::Migration[8.0]
  def change
    create_table :attractions do |t|
      t.string :name, null: false
      t.string :normalized_name
      t.text :shared_summary
      t.text :google_maps_url
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.text :address
      t.string :city
      t.string :country
      t.string :status, null: false, default: "pending"
      t.string :coordinate_fingerprint
      t.references :source_hotel, foreign_key: { to_table: :hotels }
      t.references :submitted_by, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :review_note
      t.string :archived_from_status
      t.references :merged_into, foreign_key: { to_table: :attractions }
      t.timestamps

      t.check_constraint "status IN ('pending', 'approved', 'rejected', 'archived')",
        name: "attractions_status_allowed"
      t.check_constraint "archived_from_status IS NULL OR archived_from_status IN ('pending', 'approved', 'rejected')",
        name: "attractions_archived_from_status_allowed"
      t.check_constraint "latitude IS NULL OR latitude BETWEEN -90 AND 90",
        name: "attractions_latitude_range"
      t.check_constraint "longitude IS NULL OR longitude BETWEEN -180 AND 180",
        name: "attractions_longitude_range"
    end

    add_index :attractions, :status
    add_index :attractions, :normalized_name
    add_index :attractions, %i[latitude longitude]
    add_index :attractions, :coordinate_fingerprint,
      unique: true,
      where: "coordinate_fingerprint IS NOT NULL AND status IN ('pending', 'approved')",
      name: "index_active_attractions_on_fingerprint"

    create_table :hotel_nearby_attractions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :attraction, null: false, foreign_key: true
      t.text :description
      t.timestamps
    end

    add_index :hotel_nearby_attractions, %i[hotel_id attraction_id],
      unique: true,
      name: "index_hotel_nearby_attractions_uniqueness"

    reversible do |direction|
      direction.up { copy_legacy_attractions }
    end
  end

  private

  def copy_legacy_attractions
    execute <<~SQL.squish
      INSERT INTO attractions
        (id, name, address, city, country, status, source_hotel_id, created_at, updated_at)
      SELECT
        id, name, address, city, country, 'approved', hotel_id, created_at, updated_at
      FROM nearby_attractions
      ORDER BY id
    SQL

    execute <<~SQL.squish
      SELECT setval(
        pg_get_serial_sequence('attractions', 'id'),
        COALESCE((SELECT MAX(id) FROM attractions), 1),
        EXISTS(SELECT 1 FROM attractions)
      )
    SQL

    execute <<~SQL.squish
      INSERT INTO hotel_nearby_attractions
        (hotel_id, attraction_id, description, created_at, updated_at)
      SELECT
        legacy.hotel_id,
        legacy.id,
        legacy.description,
        legacy.created_at,
        legacy.updated_at
      FROM nearby_attractions legacy
      ORDER BY legacy.id
    SQL
  end
end
