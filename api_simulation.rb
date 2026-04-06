require 'net/http'
require 'json'
require 'uri'
require 'date'

# Simulation of a Chatbot calling WAStays API
class WAStaysChatbotSimulation
  BASE_URL = "http://localhost:3000/api/v1"

  def initialize(api_key)
    @api_key = api_key
  end

  def run_simulation
    puts "--- 🤖 Starting WhatsApp Chatbot Simulation ---"
    
    # 1. Fetch available hotels
    hotels = get_request("/hotels?city=Kuala%20Lumpur")
    return unless hotels
    
    hotel = hotels.first
    if hotel
      puts "✅ Found Hotel: #{hotel['name']} (ID: #{hotel['id']})"
      
      # 2. Check availability for a specific stay
      check_in = (Date.today + 7).to_s
      check_out = (Date.today + 9).to_s
      
      availability = get_request("/hotels/#{hotel['id']}/availability?check_in=#{check_in}&check_out=#{check_out}&adults=2")
      
      if availability && availability['available_rooms'].any?
        room = availability['available_rooms'].first
        puts "✅ Room Available: #{room['name']} - Total: #{room['currency']} #{room['total_price']}"
        
        # 3. Create a Quote (Freeze price and generate link)
        quote_params = {
          hotel_id: hotel['id'],
          room_type_id: room['room_type_id'],
          check_in: check_in,
          check_out: check_out,
          adults: 2,
          room_count: 1,
          guest_name: "Sam WhatsApp",
          guest_email: "sam@example.com",
          guest_phone: "+60123456789"
        }
        
        quote = post_request("/quotes", quote_params)
        
        if quote && quote['success']
          puts "--- 🚀 Simulation Result ---"
          puts "Unique Booking Link: #{quote['booking_url']}"
          puts "Price Frozen until: #{quote['expires_at']}"
          puts "----------------------------"
        end
      else
        puts "❌ No rooms available for those dates."
      end
    else
      puts "❌ No hotels found in KL."
    end
  end

  private

  def get_request(path)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Accept"] = "application/json"

    execute(uri, request)
  end

  def post_request(path, body)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = body.to_json

    execute(uri, request)
  end

  def execute(uri, request)
    Net::HTTP.start(uri.hostname, uri.port) do |http|
      response = http.request(request)
      if response.code.to_i >= 400
        puts "❌ API Error (#{response.code}): #{response.body}"
        return nil
      end
      JSON.parse(response.body)
    end
  rescue Errno::ECONNREFUSED
    puts "❌ Connection Refused: Is the Rails server running on localhost:3000?"
    nil
  end
end

# To run this, generate a key in rails console:
# key = ApiKey.create!(name: "Test Chatbot")
# puts key.token

if ARGV.empty?
  puts "Usage: ruby api_simulation.rb YOUR_API_KEY"
else
  WAStaysChatbotSimulation.new(ARGV[0]).run_simulation
end
