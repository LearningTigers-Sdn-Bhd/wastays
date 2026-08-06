# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    BookingSource.seed_defaults!
  end
end
