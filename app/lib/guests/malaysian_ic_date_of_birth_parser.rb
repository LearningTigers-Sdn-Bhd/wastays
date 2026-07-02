# frozen_string_literal: true

module Guests
  class MalaysianIcDateOfBirthParser
    class << self
      def parse(government_id, today: Date.current)
        digits = government_id.to_s.scan(/\d/).first(6)&.join
        return if digits.blank? || digits.length < 6

        year = (today.year / 100) * 100 + digits[0, 2].to_i
        month = digits[2, 2].to_i
        day = digits[4, 2].to_i

        date_of_birth = Date.new(year, month, day)
        date_of_birth > today ? date_of_birth.prev_year(100) : date_of_birth
      rescue Date::Error
        nil
      end
    end
  end
end
