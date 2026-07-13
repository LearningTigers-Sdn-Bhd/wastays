# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::HousekeepingTasksXlsGenerator do
  let(:hotel) { create(:hotel) }

  describe "#call" do
    it "exists and can be instantiated" do
      service = described_class.new(
        hotel: hotel,
        room_groups: []
      )
      expect(service).to respond_to(:call)
    end
  end
end
