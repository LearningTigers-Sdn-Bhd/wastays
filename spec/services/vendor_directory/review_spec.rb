# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorDirectory::Review do
  describe "#rating_i" do
    # Two sources build this shape: the fixture, which YAML parses into an
    # Integer, and a submitted form, which arrives as a String. The vendor's
    # average has to add them up either way.
    it "reads an integer rating whether it arrived as a number or a string" do
      from_fixture = described_class.new(
        guest_name: "Aisha", rating: 5, comment: "Lovely", posted_at: Time.current
      )
      from_form = described_class.new(
        guest_name: "Aisha", rating: "4", comment: "Lovely", posted_at: Time.current
      )

      expect(from_fixture.rating_i).to eq(5)
      expect(from_form.rating_i).to eq(4)
    end
  end
end
