
require_relative "../config/environment"
puts "Hotel Amenities in Database: #{Amenity.hotel.pluck(:slug).join(', ')}"
