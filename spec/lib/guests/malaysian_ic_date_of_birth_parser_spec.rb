require 'rails_helper'

RSpec.describe Guests::MalaysianIcDateOfBirthParser do
  describe '.parse' do
    it 'parses the first six digits as a date of birth' do
      expect(described_class.parse('010203-10-1234')).to eq(Date.new(2001, 2, 3))
    end

    it 'uses the previous century when the parsed date would be in the future' do
      travel_to(Date.new(2026, 7, 2)) do
        expect(described_class.parse('300101-10-1234')).to eq(Date.new(1930, 1, 1))
      end
    end

    it 'returns nil for invalid input' do
      expect(described_class.parse('991332-10-1234')).to be_nil
      expect(described_class.parse('abc')).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end
  end
end
