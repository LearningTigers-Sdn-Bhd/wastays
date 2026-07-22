# frozen_string_literal: true

# Freezes the clock to noon UTC for the current date so that UTC and the common
# hotel/user zones (e.g. Kuala Lumpur +8, Eastern -5) all resolve to the same
# calendar date. Business-date logic derives "today" from the request zone while
# specs seed BusinessDates::ResetAuthority from Date.current (UTC); when the real
# clock sits near a zone midnight the two diverge and check-in style specs flake.
# Pinning to noon UTC removes that boundary sensitivity without touching the seed.
#
# Opt in per example group with the :business_day tag.
RSpec.configure do |config|
  config.around(:each, :business_day) do |example|
    travel_to(Time.current.change(hour: 12, min: 0, sec: 0, usec: 0)) do
      example.run
    end
  end
end
