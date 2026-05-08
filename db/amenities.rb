# frozen_string_literal: true

require 'json'

module AmenitiesSeeder
  module_function

  def run
    SeedLog.section('Seeding Amenities')

    data_path = Rails.root.join('db', 'amenities_data.json')
    
    unless File.exist?(data_path)
      SeedLog.step("Warning: db/amenities_data.json not found. Skipping.")
      return
    end

    amenities_data = JSON.parse(File.read(data_path))

    amenities_data.each do |attrs|
      Amenity.find_or_initialize_by(slug: attrs['slug'], amenity_type: attrs['amenity_type']).tap do |amenity|
        amenity.name = attrs['name']
        amenity.icon = attrs['icon']
        amenity.category = attrs['category']
        amenity.channex_id = attrs['channex_id']
        amenity.save!
      end
    end

    SeedLog.ok("#{amenities_data.size} amenities synchronized from JSON")
  end
end
