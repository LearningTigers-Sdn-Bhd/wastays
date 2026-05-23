# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    # We use create instead of build to ensure they are in the DB.
    # Since transactional fixtures are on, we might need to recreate them if they are cleared.
    # But wait, before(:suite) runs once. If transactional fixtures are on,
    # everything created here might be rolled back?
    # Actually, RSpec transactional fixtures start AFTER before(:suite).

    # Common Hotel Amenities
    [
      { name: "Free WiFi", slug: "wifi", category: "Services", amenity_type: "hotel" },
      { name: "Swimming Pool", slug: "swimming_pool", category: "Facilities", amenity_type: "hotel" },
      { name: "Fitness Center", slug: "fitness_center", category: "Facilities", amenity_type: "hotel" },
      { name: "Spa & Wellness Centre", slug: "spa_wellness_centre", category: "Facilities", amenity_type: "hotel" },
      { name: "Laundry", slug: "laundry", category: "Facilities", amenity_type: "hotel" }
    ].each do |attr|
      amenity = Amenity.find_or_initialize_by(slug: attr[:slug], amenity_type: attr[:amenity_type])
      amenity.update!(
        name: attr[:name],
        category: attr[:category],
        icon: "check"
      )
    end

    # Common Room Amenities
    [
      { name: "Free WiFi", slug: "wifi", category: "Connectivity", amenity_type: "room" },
      { name: "Air Conditioning", slug: "ac", category: "Comfort", amenity_type: "room" },
      { name: "Balcony / Terrace", slug: "balcony", category: "View", amenity_type: "room" },
      { name: "Flat-screen TV", slug: "tv", category: "Entertainment", amenity_type: "room" }
    ].each do |attr|
      amenity = Amenity.find_or_initialize_by(slug: attr[:slug], amenity_type: attr[:amenity_type])
      amenity.update!(
        name: attr[:name],
        category: attr[:category],
        icon: "check"
      )
    end
  end
end
