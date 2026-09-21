# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorDirectory::Category do
  describe "#to_param" do
    it "is the slug, so a category routes by name rather than by position" do
      category = described_class.new(
        slug: "food-drink", name: "Food & Drink", tagline: "Eat nearby", icon: "utensils"
      )

      expect(category.to_param).to eq("food-drink")
      expect(Rails.application.routes.url_helpers.concierge_recommendations_path(
        hotel_code: "10101", public_id: SecureRandom.uuid, category: category
      )).to include("category=food-drink")
    end
  end
end
